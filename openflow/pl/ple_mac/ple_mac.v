// PL Ethernet MAC front end (RGMII, 1 Gb/s) for the ZYNQ MINI, controlled from Linux over M_AXI_GP0 (0x40000000).
// The PL does the RGMII timing, sends a frame from a buffer (preamble, SFD, data, inter-frame gap) and captures one received
// frame raw (everything after DV rises, preamble included). Protocol work (ARP, ICMP, UDP, FCS) is done by software on the PS.
//   0x00 ID "MAC1"  0x04 scratch  0x1C MDIO ctl {mdio_release, mdc, phy_reset_n}  0x20 MDIO pin level
//   0x24 CTRL  (write) bit0 transmit the frame in the TX buffer, bit1 release the RX buffer (ack), bit2 clear counters
//   0x28 STATUS bit0 rx_ready, bit1 tx_busy, bits7:4 RGMII in-band status {duplex, speed[1:0], link}
//   0x2C RX_LEN raw bytes captured  0x30 TX_LEN bytes to send (after preamble; includes FCS)  0x34 frames rx  0x38 frames tx  0x3C frames missed
//   CTRL bit3 arms the debug logic analyzer (STATUS bit8 = captured); 0xA00.. its 256 samples (write pointer in [31:24], sample {rc2,rc1,rd2,rd1} in [9:0]; oldest sample = write pointer)
//   0x400.. RX buffer, one captured byte per register (320 bytes, read-only)   0x200.. TX buffer (80 words, little-endian bytes, write-only)
//   0xA00.. analyzer samples
module ple_mac(input clk50, input [1:0] key, output [3:0] led,
               output phy_rst_n, output phy_mdc, inout phy_mdio,
               output rgmii_txc, output rgmii_tx_ctl, output [3:0] rgmii_txd,
               input rgmii_rxc, input rgmii_rx_ctl, input [3:0] rgmii_rxd);
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

  // ---- 125 MHz transmit clock ----
  wire clkfb, clkfb_b, c0, locked, clk125;
  MMCME2_BASE #(.CLKIN1_PERIOD(20.0), .CLKFBOUT_MULT_F(20.0), .DIVCLK_DIVIDE(1), .CLKOUT0_DIVIDE_F(8.0)) mmcm (
      .CLKIN1(clk50), .CLKFBIN(clkfb_b), .CLKFBOUT(clkfb), .CLKOUT0(c0), .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0),
      .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6());
  BUFG bf (.I(clkfb), .O(clkfb_b));
  BUFG b0 (.I(c0), .O(clk125));

  // ---- registers in the AXI clock domain ----
  reg [31:0] scratch = 0, tx_len = 0;
  reg prst = 0, pmdc = 0, pmdio_rel = 1;
  reg tx_go_tog = 0, rx_ack_tog = 0, clr_tog = 0, la_arm_tog = 0;
  reg [31:0] txw [0:79];
  assign phy_rst_n = prst; assign phy_mdc = pmdc; assign phy_mdio = pmdio_rel ? 1'bz : 1'b0;

  // ---- transmit (clk125 domain) ----
  reg [2:0] go_s = 0; reg tx_busy = 0; reg tx_seen = 0;
  reg [7:0] txd8 = 0; reg txen = 0; reg [31:0] tx_idx = 0; reg [3:0] tx_ph = 0; reg [2:0] tx_st = 0;
  reg [31:0] frames_tx = 0;
  reg [2:0] clr_s125 = 0; reg clr_seen125 = 0;
  localparam T_IDLE = 0, T_PRE = 1, T_SFD = 2, T_DATA = 3, T_GAP = 4;
  wire [31:0] tword = txw[tx_idx[8:2]];
  wire [7:0] tbyte = tx_idx[1:0] == 0 ? tword[7:0] : tx_idx[1:0] == 1 ? tword[15:8] : tx_idx[1:0] == 2 ? tword[23:16] : tword[31:24];
  always @(posedge clk125) begin
    go_s <= {go_s[1:0], tx_go_tog}; clr_s125 <= {clr_s125[1:0], clr_tog};
    if (clr_s125[2] != clr_seen125) begin clr_seen125 <= clr_s125[2]; frames_tx <= 0; end
    case (tx_st)
      T_IDLE: begin txen <= 0; txd8 <= 0;
                if (go_s[2] != tx_seen) begin tx_seen <= go_s[2]; tx_busy <= 1; tx_st <= T_PRE; tx_ph <= 0; end end
      T_PRE:  begin txen <= 1; txd8 <= 8'h55; tx_ph <= tx_ph + 1; if (tx_ph == 6) tx_st <= T_SFD; end
      T_SFD:  begin txen <= 1; txd8 <= 8'hD5; tx_idx <= 0; tx_st <= T_DATA; end
      T_DATA: begin txen <= 1; txd8 <= tbyte; tx_idx <= tx_idx + 1;
                if (tx_idx + 1 >= tx_len) begin tx_st <= T_GAP; tx_ph <= 0; end end
      T_GAP:  begin txen <= 0; txd8 <= 0; tx_ph <= tx_ph + 1; if (tx_ph == 15) begin tx_st <= T_IDLE; tx_busy <= 0; frames_tx <= frames_tx + 1; end end
    endcase
  end
  genvar i;
  generate for (i = 0; i < 4; i = i + 1) begin : g_txd
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) o (.Q(rgmii_txd[i]), .C(clk125), .CE(1'b1), .D1(txd8[i]), .D2(txd8[i+4]), .R(1'b0), .S(1'b0));
  end endgenerate
  ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) o_ctl (.Q(rgmii_tx_ctl), .C(clk125), .CE(1'b1), .D1(txen), .D2(txen), .R(1'b0), .S(1'b0));
  ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) o_clk (.Q(rgmii_txc), .C(clk125), .CE(1'b1), .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0));

  // ---- receive (PHY's RXC, sampled on the inverted clock: this PHY does not delay RXC) ----
  wire rxc_ibuf, rx_clk;
  IBUF ib_rxc (.I(rgmii_rxc), .O(rxc_ibuf));
  BUFG bg_rxc (.I(~rxc_ibuf), .O(rx_clk));
  wire [3:0] rd1, rd2; wire rc1, rc2;
  generate for (i = 0; i < 4; i = i + 1) begin : g_rxd
    IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED")) q (.Q1(rd1[i]), .Q2(rd2[i]), .C(rx_clk), .CE(1'b1), .D(rgmii_rxd[i]), .R(1'b0), .S(1'b0));
  end endgenerate
  IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED")) q_ctl (.Q1(rc1), .Q2(rc2), .C(rx_clk), .CE(1'b1), .D(rgmii_rx_ctl), .R(1'b0), .S(1'b0));
  reg [7:0] rxb [0:511];                 // received bytes, written whole (one byte per rx_clk)
  reg [8:0] rx_idx = 0; reg [8:0] rx_len = 0; reg rx_ready = 0, rx_active = 0, rx_miss_arm = 0;
  reg [31:0] frames_rx = 0, missed = 0; reg [3:0] rgmii_stat = 0;
  reg [2:0] ack_s = 0; reg ack_seen = 0; reg [2:0] clr_srx = 0; reg clr_seenrx = 0;
  wire [7:0] rx8 = {rd2, rd1};
  wire rdv = rc1;                                      // RGMII: RX_CTL on the first (rising) edge is DV, on the second it is DV xor ER
  always @(posedge rx_clk) begin
    ack_s <= {ack_s[1:0], rx_ack_tog}; clr_srx <= {clr_srx[1:0], clr_tog};
    if (ack_s[2] != ack_seen) begin ack_seen <= ack_s[2]; rx_ready <= 0; end
    if (clr_srx[2] != clr_seenrx) begin clr_seenrx <= clr_srx[2]; frames_rx <= 0; missed <= 0; end
    if (!rdv) rgmii_stat <= rd1;                       // in-band status while the line is idle: {duplex, speed, link}
    if (rdv && !rx_active) begin
      if (!rx_ready) begin rx_active <= 1; rxb[0] <= rx8; rx_idx <= 1; end
      else if (!rx_miss_arm) begin rx_miss_arm <= 1; missed <= missed + 1; end
    end else if (rdv && rx_active) begin
      if (rx_idx < 320) begin rxb[rx_idx] <= rx8; rx_idx <= rx_idx + 1; end
    end else if (!rdv) begin
      rx_miss_arm <= 0;
      if (rx_active) begin rx_active <= 0; rx_len <= rx_idx; rx_ready <= 1; frames_rx <= frames_rx + 1; end
    end
  end


  // ---- debug logic analyzer: circular buffer of the raw RGMII samples {rc2, rc1, rd2, rd1}, frozen 96 samples after DV rises ----
  reg [9:0] la [0:255]; reg [7:0] la_wp = 0; reg la_run = 0, la_done = 0, la_prev = 0; reg [7:0] la_cnt = 0;
  reg [2:0] la_arm_s = 0; reg la_arm_seen = 0;
  always @(posedge rx_clk) begin
    la_arm_s <= {la_arm_s[1:0], la_arm_tog};
    if (la_arm_s[2] != la_arm_seen) begin la_arm_seen <= la_arm_s[2]; la_run <= 1; la_done <= 0; la_cnt <= 0; end
    la_prev <= rc1;
    if (la_run) begin
      la[la_wp] <= {rc2, rc1, rd2, rd1};
      la_wp <= la_wp + 1;
      if (la_cnt != 0) begin la_cnt <= la_cnt + 1; if (la_cnt == 8'd96) begin la_run <= 0; la_done <= 1; end end
      else if (rc1 && !la_prev) la_cnt <= 1;
    end
  end
  reg [1:0] la_done_s = 0; always @(posedge aclk) la_done_s <= {la_done_s[0], la_done};

  // ---- AXI-clock views of the RX/TX flags ----
  reg [1:0] rdy_s = 0, busy_s = 0; reg [3:0] st_s0 = 0, st_s1 = 0;
  always @(posedge aclk) begin rdy_s <= {rdy_s[0], rx_ready}; busy_s <= {busy_s[0], tx_busy}; st_s0 <= rgmii_stat; st_s1 <= st_s0; end

  // ---- GP0 register slave ----
  wire do_wr = awvalid & wvalid & ~bvalid;
  wire do_rd = arvalid & ~rvalid;
  wire [9:0] wa = awaddr[11:2], ra = araddr[11:2];
  always @(posedge aclk) begin
    awready <= 0; wready <= 0; arready <= 0;
    if (do_wr && !awready) begin
      awready <= 1; wready <= 1; bvalid <= 1; bid <= awid;
      if (wa >= 10'd128 && wa < 10'd208) txw[wa - 10'd128] <= wdata;
      else case (wa)
        10'd1:  scratch <= wdata;
        10'd7:  begin prst <= wdata[0]; pmdc <= wdata[1]; pmdio_rel <= wdata[2]; end
        10'd9:  begin if (wdata[3]) la_arm_tog <= ~la_arm_tog; if (wdata[0]) tx_go_tog <= ~tx_go_tog; if (wdata[1]) rx_ack_tog <= ~rx_ack_tog; if (wdata[2]) clr_tog <= ~clr_tog; end
        10'd12: tx_len <= wdata;
        default: ;
      endcase
    end
    if (bvalid && bready) bvalid <= 0;
    if (do_rd && !arready) begin
      arready <= 1; rvalid <= 1; rid <= arid;
      if (ra >= 10'd640 && ra < 10'd896) rdata <= {la_wp, 14'b0, la[ra - 10'd640]};
      else if (ra >= 10'd256 && ra < 10'd576) rdata <= {24'b0, rxb[ra - 10'd256]};
      else case (ra)
        10'd0:  rdata <= 32'h4D414331;
        10'd1:  rdata <= scratch;
        10'd7:  rdata <= {29'b0, pmdio_rel, pmdc, prst};
        10'd8:  rdata <= {31'b0, phy_mdio};
        10'd10: rdata <= {23'b0, la_done_s[1], st_s1, 2'b0, busy_s[1], rdy_s[1]};
        10'd11: rdata <= {23'b0, rx_len};
        10'd12: rdata <= tx_len;
        10'd13: rdata <= frames_rx;
        10'd14: rdata <= frames_tx;
        10'd15: rdata <= missed;
        default: rdata <= 32'hDEADBEEF;
      endcase
    end
    if (rvalid && rready) rvalid <= 0;
  end
  assign led = {st_s1[0], busy_s[1], rdy_s[1], key[0]};
endmodule
