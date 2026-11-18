// PL Ethernet RGMII loopback test: RTL8211E in digital loopback (set over MDIO by the PS), no cable needed.
// PS (M_AXI_GP0 @ 0x40000000) bit-bangs MDIO, starts a frame, reads back the captured RX bytes and counters.
module ple_rgmii(input clk50, input [1:0] key, output [3:0] led,
                 output phy_rst_n, output phy_mdc, inout phy_mdio,
                 output rgmii_txc, output rgmii_tx_ctl, output [3:0] rgmii_txd,
                 input rgmii_rxc, input rgmii_rx_ctl, input [3:0] rgmii_rxd);
  parameter TXC_PHASE = 0;   // 0 or 90 (degrees of the forwarded TX clock)
  parameter RX_INV = 1;      // 1: sample RGMII RX on the inverted RXC (needed on this board: the PHY does not delay RXC)
  wire [3:0] fclk, frst; wire aclk;
  wire [31:0] araddr, awaddr, wdata; wire arvalid, awvalid, wvalid, bready, rready;
  wire [11:0] arid, awid;
  reg arready = 0, awready = 0, wready = 0, bvalid = 0, rvalid = 0;
  reg [11:0] bid = 0, rid = 0; reg [31:0] rdata = 0;
  PS7 ps7 (
    .FCLKCLK(fclk), .FCLKRESETN(frst), .MAXIGP0ACLK(aclk),
    .MAXIGP0ARADDR(araddr), .MAXIGP0ARVALID(arvalid), .MAXIGP0ARREADY(arready), .MAXIGP0ARID(arid),
    .MAXIGP0AWADDR(awaddr), .MAXIGP0AWVALID(awvalid), .MAXIGP0AWREADY(awready), .MAXIGP0AWID(awid),
    .MAXIGP0WDATA(wdata), .MAXIGP0WVALID(wvalid), .MAXIGP0WREADY(wready),
    .MAXIGP0BVALID(bvalid), .MAXIGP0BREADY(bready), .MAXIGP0BID(bid), .MAXIGP0BRESP(2'b00),
    .MAXIGP0RVALID(rvalid), .MAXIGP0RREADY(rready), .MAXIGP0RID(rid), .MAXIGP0RLAST(1'b1),
    .MAXIGP0RDATA(rdata), .MAXIGP0RRESP(2'b00));
  BUFG bufg_aclk (.I(fclk[0]), .O(aclk));

  // ---- 125 MHz TX clock from clk50 (0 and 90 degrees) ----
  wire clkfb, clkfb_b, c0, c1, c0b, c1b, locked, clk125, clk125_90;
  MMCME2_BASE #(.CLKIN1_PERIOD(20.0), .CLKFBOUT_MULT_F(20.0), .DIVCLK_DIVIDE(1),
                .CLKOUT0_DIVIDE_F(8.0), .CLKOUT1_DIVIDE(8), .CLKOUT1_PHASE(90.0)) mmcm (
      .CLKIN1(clk50), .CLKFBIN(clkfb_b), .CLKFBOUT(clkfb), .CLKOUT0(c0), .CLKOUT1(c1),
      .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0),
      .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(),
      .CLKOUT4(), .CLKOUT5(), .CLKOUT6());
  BUFG bf (.I(clkfb), .O(clkfb_b));
  BUFG b0 (.I(c0), .O(clk125));
  BUFG b1 (.I(c1), .O(clk125_90));

  // ---- registers / AXI ----
  reg [31:0] scratch = 0;
  reg prst = 0, pmdc = 0, pmdio_rel = 1;
  reg [3:0] ledr = 0;
  assign phy_rst_n = prst; assign phy_mdc = pmdc; assign phy_mdio = pmdio_rel ? 1'bz : 1'b0;
  assign led = ledr;

  // ---- TX frame generator on clk125 ----
  reg [2:0] go_s = 0; reg go_clr = 0; reg go = 0;
  reg [7:0] txd8 = 0; reg txen = 0; reg [9:0] txcnt = 0; reg txbusy = 0;
  reg [9:0] txlen = 10'd60;      // bytes in frame after SFD (payload)
  always @(posedge clk125) begin
    go_s <= {go_s[1:0], go};
    if (!txbusy) begin
      txen <= 0; txd8 <= 0;
      if (go_s[2]) begin txbusy <= 1; txcnt <= 0; end
    end else begin
      txen <= 1; txcnt <= txcnt + 1;
      if (txcnt < 7) txd8 <= 8'h55;
      else if (txcnt == 7) txd8 <= 8'hD5;
      else txd8 <= txcnt[7:0] - 8'd8;           // payload: 0,1,2,...
      if (txcnt == 8 + txlen) begin txbusy <= 0; txen <= 0; end
    end
  end
  // ODDRs: rising = low nibble, falling = high nibble
  genvar i;
  generate for (i = 0; i < 4; i = i + 1) begin : g_txd
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) o (.Q(rgmii_txd[i]), .C(clk125), .CE(1'b1), .D1(txd8[i]), .D2(txd8[i+4]), .R(1'b0), .S(1'b0));
  end endgenerate
  ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) o_ctl (.Q(rgmii_tx_ctl), .C(clk125), .CE(1'b1), .D1(txen), .D2(txen), .R(1'b0), .S(1'b0));
  wire txc_src = (TXC_PHASE == 90) ? clk125_90 : clk125;
  ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) o_clk (.Q(rgmii_txc), .C(txc_src), .CE(1'b1), .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0));

  // ---- RX capture on the PHY's RXC ----
  wire rxc_b, rxc_ibuf;
  IBUF ib_rxc (.I(rgmii_rxc), .O(rxc_ibuf));
  wire rxc_src = (RX_INV == 1) ? ~rxc_ibuf : rxc_ibuf;
  BUFG bg_rxc (.I(rxc_src), .O(rxc_b));
  wire [3:0] rd1, rd2; wire rc1, rc2;
  generate for (i = 0; i < 4; i = i + 1) begin : g_rxd
    IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED")) q (.Q1(rd1[i]), .Q2(rd2[i]), .C(rxc_b), .CE(1'b1), .D(rgmii_rxd[i]), .R(1'b0), .S(1'b0));
  end endgenerate
  IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED")) q_ctl (.Q1(rc1), .Q2(rc2), .C(rxc_b), .CE(1'b1), .D(rgmii_rx_ctl), .R(1'b0), .S(1'b0));
  // capture first 80 bytes from the first DV rising edge after arm
  reg arm = 0; reg [2:0] arm_s = 0;
  reg [7:0] cap [0:79];
  reg [6:0] capn = 0; reg capdone = 0; reg capping = 0;
  reg [31:0] rxclkcnt = 0, dvcnt = 0;
  reg [3:0] rd2_p = 0; always @(posedge rxc_b) rd2_p <= rd2;
  wire [7:0] rx8 = (RX_INV == 1) ? {rd1, rd2_p} : {rd2, rd1};
  wire dv_any = rc1 | rc2;
  integer k;
  always @(posedge rxc_b) begin
    arm_s <= {arm_s[1:0], arm};
    rxclkcnt <= rxclkcnt + 1;
    if (dv_any) dvcnt <= dvcnt + 1;
    if (!arm_s[2]) begin capn <= 0; capdone <= 0; capping <= 0; end
    else if (!capdone) begin
      if (dv_any && !capping) capping <= 1;
      if (dv_any || capping) begin
        cap[capn] <= rx8; capn <= capn + 1;
        if (capn == 7'd79) capdone <= 1;
      end
    end
  end

  // ---- AXI slave ----
  wire do_wr = awvalid & wvalid & ~bvalid;
  wire do_rd = arvalid & ~rvalid;
  reg [31:0] t_dvsnap = 0;
  always @(posedge aclk) begin
    awready <= 0; wready <= 0; arready <= 0;
    if (do_wr && !awready) begin
      awready <= 1; wready <= 1; bvalid <= 1; bid <= awid;
      case (awaddr[7:2])
        6'h01: scratch <= wdata;
        6'h03: ledr <= wdata[3:0];
        6'h07: begin prst <= wdata[0]; pmdc <= wdata[1]; pmdio_rel <= wdata[2]; end
        6'h09: begin go <= wdata[0]; arm <= wdata[1]; end
        6'h0a: txlen <= wdata[9:0];
        default: ;
      endcase
    end
    if (bvalid && bready) bvalid <= 0;
    if (do_rd && !arready) begin
      arready <= 1; rvalid <= 1; rid <= arid;
      if (araddr[7:2] >= 6'h10 && araddr[7:2] < 6'h10 + 6'd20) begin
        // 80 captured bytes packed 4 per word
        rdata <= {cap[{araddr[6:2] - 5'd16, 2'd3}], cap[{araddr[6:2] - 5'd16, 2'd2}],
                  cap[{araddr[6:2] - 5'd16, 2'd1}], cap[{araddr[6:2] - 5'd16, 2'd0}]};
      end else case (araddr[7:2])
        6'h00: rdata <= 32'h4D494931;      // "MII1"
        6'h01: rdata <= scratch;
        6'h07: rdata <= {29'b0, pmdio_rel, pmdc, prst};
        6'h08: rdata <= {31'b0, phy_mdio};
        6'h09: rdata <= {29'b0, txbusy, arm, go};
        6'h0b: rdata <= {30'b0, capdone, locked};
        6'h0c: rdata <= rxclkcnt;
        6'h0d: rdata <= dvcnt;
        default: rdata <= 32'hDEADBEEF;
      endcase
    end
    if (rvalid && rready) rvalid <= 0;
  end
endmodule
