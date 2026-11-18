// zm_base: the open-flow counterpart of the Vivado "pltest" overlay, one design with everything on M_AXI_GP0 (0x40000000):
//   0x000 ID "ZMB1"  0x004 scratch  0x008 {MMCM locked}
//   0x010 LEDS (4 bits)   0x014 KEYS (pin levels, 0 = pressed)
//   0x020/0x024 HDR_OUT0/1   0x028/0x02C HDR_TRI0/1 (1 = input, the reset state)   0x030/0x034 HDR_IN0/1     (34 header signals)
//   0x040 I2C   W: bit0 SCL, bit1 SDA release        R: bit0 SCL, bit1 SDA pin
//   0x050 OLED pins (4 bits: D0 SCLK, D1 MOSI, DC, RES)
//   0x060 PHY   W: bit0 reset_n, bit1 MDC, bit2 MDIO release        0x064 R: bit0 MDIO pin
//   0x070 TIMER ctrl (bit0 enable, bit1 irq enable)  0x074 period (aclk cycles)  0x078 count  0x07C status (bit0 pending, write 1 clears)
//   0x080..0x094 clock meters (cycles in a 2^20-aclk window): clk50, mmcm 100, 150, 200, FCLK1, FCLK2     0x098 window counter
//   0x108 DMA SRC  0x10C DST  0x110 LEN  0x114 CTRL (b0 start, b1 checksum-only, b2 clear, b3 irq enable)  0x118 STATUS (b0 busy, b1 done, b2 err)
//   0x11C CHECKSUM  0x120 CYCLES  0x124 BYTES
// IRQ_F2P[0] = timer interrupt OR (DMA done AND irq enable).
module zm_base(input clk50, input [1:0] key, output [3:0] led,
               inout [33:0] hdr, output eeprom_scl, inout eeprom_sda, output [3:0] oled,
               output phy_rst_n, output phy_mdc, inout phy_mdio);
  wire [3:0] fclk, frst; wire aclk;
  wire [31:0] araddr, awaddr, wdata; wire arvalid, awvalid, wvalid, bready, rready;
  wire [11:0] arid, awid;
  reg arready = 0, awready = 0, wready = 0, bvalid = 0, rvalid = 0;
  reg [11:0] bid = 0, rid = 0; reg [31:0] rdata = 0;
  // ---- HP0 master ----
  reg  [31:0] hp_araddr = 0; reg hp_arvalid = 0; wire hp_arready;
  wire [63:0] hp_rdata; wire hp_rvalid, hp_rlast; wire [1:0] hp_rresp; reg hp_rready = 0;
  reg  [31:0] hp_awaddr = 0; reg hp_awvalid = 0; wire hp_awready;
  reg  [63:0] hp_wdata = 0; reg hp_wvalid = 0, hp_wlast = 0; wire hp_wready;
  wire hp_bvalid; wire [1:0] hp_bresp; reg hp_bready = 0;
  wire irq;
  PS7 ps7 (
    .FCLKCLK(fclk), .FCLKRESETN(frst), .MAXIGP0ACLK(aclk), .SAXIHP0ACLK(aclk),
    .MAXIGP0ARADDR(araddr), .MAXIGP0ARVALID(arvalid), .MAXIGP0ARREADY(arready), .MAXIGP0ARID(arid),
    .MAXIGP0AWADDR(awaddr), .MAXIGP0AWVALID(awvalid), .MAXIGP0AWREADY(awready), .MAXIGP0AWID(awid),
    .MAXIGP0WDATA(wdata), .MAXIGP0WVALID(wvalid), .MAXIGP0WREADY(wready),
    .MAXIGP0BVALID(bvalid), .MAXIGP0BREADY(bready), .MAXIGP0BID(bid), .MAXIGP0BRESP(2'b00),
    .MAXIGP0RVALID(rvalid), .MAXIGP0RREADY(rready), .MAXIGP0RID(rid), .MAXIGP0RLAST(1'b1),
    .MAXIGP0RDATA(rdata), .MAXIGP0RRESP(2'b00),
    .SAXIHP0ARADDR(hp_araddr), .SAXIHP0ARVALID(hp_arvalid), .SAXIHP0ARREADY(hp_arready),
    .SAXIHP0ARBURST(2'b01), .SAXIHP0ARLEN(4'd15), .SAXIHP0ARSIZE(2'b11), .SAXIHP0ARID(6'd0),
    .SAXIHP0ARCACHE(4'b0011), .SAXIHP0ARPROT(3'b000), .SAXIHP0ARLOCK(2'b00), .SAXIHP0ARQOS(4'd0),
    .SAXIHP0RDATA(hp_rdata), .SAXIHP0RVALID(hp_rvalid), .SAXIHP0RREADY(hp_rready), .SAXIHP0RLAST(hp_rlast), .SAXIHP0RRESP(hp_rresp),
    .SAXIHP0AWADDR(hp_awaddr), .SAXIHP0AWVALID(hp_awvalid), .SAXIHP0AWREADY(hp_awready),
    .SAXIHP0AWBURST(2'b01), .SAXIHP0AWLEN(4'd15), .SAXIHP0AWSIZE(2'b11), .SAXIHP0AWID(6'd0),
    .SAXIHP0AWCACHE(4'b0011), .SAXIHP0AWPROT(3'b000), .SAXIHP0AWLOCK(2'b00), .SAXIHP0AWQOS(4'd0),
    .SAXIHP0WDATA(hp_wdata), .SAXIHP0WVALID(hp_wvalid), .SAXIHP0WREADY(hp_wready), .SAXIHP0WLAST(hp_wlast),
    .SAXIHP0WID(6'd0), .SAXIHP0WSTRB(8'hFF),
    .SAXIHP0BVALID(hp_bvalid), .SAXIHP0BREADY(hp_bready), .SAXIHP0BRESP(hp_bresp),
    .IRQF2P({19'b0, irq}));
  BUFG bufg_aclk (.I(fclk[0]), .O(aclk));
  wire fclk1, fclk2; BUFG bf1 (.I(fclk[1]), .O(fclk1)); BUFG bf2 (.I(fclk[2]), .O(fclk2));

  // ---- clocks from the PL oscillator: 100/150/200 MHz (VCO 1200 MHz) ----
  wire clkfb, clkfb_b, c0, c1, c2, locked, m100, m150, m200;
  MMCME2_BASE #(.CLKIN1_PERIOD(20.0), .CLKFBOUT_MULT_F(24.0), .DIVCLK_DIVIDE(1), .CLKOUT0_DIVIDE_F(12.0), .CLKOUT1_DIVIDE(8), .CLKOUT2_DIVIDE(6)) mmcm (
      .CLKIN1(clk50), .CLKFBIN(clkfb_b), .CLKFBOUT(clkfb), .CLKOUT0(c0), .CLKOUT1(c1), .CLKOUT2(c2), .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0),
      .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6());
  BUFG bfb (.I(clkfb), .O(clkfb_b)); BUFG b0 (.I(c0), .O(m100)); BUFG b1 (.I(c1), .O(m150)); BUFG b2 (.I(c2), .O(m200));
  wire [31:0] d50, d100, d150, d200, df1, df2; wire [31:0] win;
  meter ma (.aclk(aclk), .clk(clk50), .delta(d50)); meter mb (.aclk(aclk), .clk(m100), .delta(d100));
  meter mc (.aclk(aclk), .clk(m150), .delta(d150)); meter md (.aclk(aclk), .clk(m200), .delta(d200));
  meter me (.aclk(aclk), .clk(fclk1), .delta(df1));  meter mf (.aclk(aclk), .clk(fclk2), .delta(df2));
  reg [19:0] w = 0; reg [31:0] wcount = 0;
  always @(posedge aclk) begin w <= w + 1; if (&w) wcount <= wcount + 1; end

  // ---- simple I/O registers ----
  reg [31:0] scratch = 0, hdr_out0 = 0, hdr_tri0 = 32'hFFFFFFFF;
  reg [1:0] hdr_out1 = 0, hdr_tri1 = 2'b11; reg [3:0] ledr = 0, oledr = 0;
  reg scl = 1, sda_rel = 1, prst = 0, pmdc = 0, pmdio_rel = 1;
  reg [1:0] ks0 = 2'b11, ks1 = 2'b11; reg [31:0] hs0 [0:0]; reg [33:0] hin_s0 = 0, hin_s1 = 0;
  wire [33:0] hdr_out = {hdr_out1, hdr_out0}, hdr_oe = ~{hdr_tri1, hdr_tri0};
  genvar i;
  generate for (i = 0; i < 34; i = i + 1) begin : g_hdr
    assign hdr[i] = hdr_oe[i] ? hdr_out[i] : 1'bz;
  end endgenerate
  always @(posedge aclk) begin ks0 <= key; ks1 <= ks0; hin_s0 <= hdr; hin_s1 <= hin_s0; end
  assign eeprom_scl = scl; assign eeprom_sda = sda_rel ? 1'bz : 1'b0;
  assign oled = oledr; assign led = ledr;
  assign phy_rst_n = prst; assign phy_mdc = pmdc; assign phy_mdio = pmdio_rel ? 1'bz : 1'b0;

  // ---- timer ----
  reg tm_en = 0, tm_ien = 0, tm_pend = 0; reg [31:0] tm_period = 1000000, tm_count = 0;
  reg tm_clr_tog = 0, tm_clr_d = 0;
  always @(posedge aclk) begin
    tm_clr_d <= tm_clr_tog;
    if (tm_clr_tog != tm_clr_d) tm_pend <= 0;
    if (tm_en) begin
      if (tm_count + 1 >= tm_period) begin tm_count <= 0; tm_pend <= 1; end else tm_count <= tm_count + 1;
    end else tm_count <= 0;
  end

  // ---- DMA engine (HP0), as in hp_dma ----
  reg [31:0] src = 0, dst = 0, len = 0, rem = 0, sa = 0, da = 0, csum = 0, cycles = 0, bytes_done = 0;
  reg mode = 0, irq_en = 0, busy = 0, done = 0, err = 0;
  reg start_tog = 0, clr_tog = 0, start_d = 0, clr_d = 0;
  wire start = start_tog ^ start_d, clr = clr_tog ^ clr_d;
  reg [63:0] buffer [0:15]; reg [4:0] beat = 0;
  localparam IDLE = 0, AR = 1, RD = 2, AW = 3, WR = 4, BR = 5, NEXT = 6;
  reg [2:0] st = IDLE;
  assign irq = (tm_pend & tm_ien) | (done & irq_en);
  always @(posedge aclk) begin
    if (clr) begin done <= 0; err <= 0; end
    case (st)
      IDLE: if (start) begin
              if (src[6:0] != 0 || len[6:0] != 0 || (!mode && dst[6:0] != 0)) begin done <= 1; err <= 1; end     // misaligned: bursts would cross 4 KiB boundaries, reject
              else begin busy <= 1; done <= 0; err <= 0; rem <= len; sa <= src; da <= dst; csum <= 0; cycles <= 0; bytes_done <= 0; st <= (len == 0) ? NEXT : AR; end
            end
      AR:  begin hp_araddr <= sa; hp_arvalid <= 1; if (hp_arvalid && hp_arready) begin hp_arvalid <= 0; hp_rready <= 1; beat <= 0; st <= RD; end end
      RD:  if (hp_rvalid && hp_rready) begin
             buffer[beat[3:0]] <= hp_rdata; beat <= beat + 1; csum <= csum + hp_rdata[31:0] + hp_rdata[63:32];
             if (hp_rresp != 0) err <= 1;
             if (hp_rlast) begin hp_rready <= 0; st <= mode ? NEXT : AW; end
           end
      AW:  begin hp_awaddr <= da; hp_awvalid <= 1; if (hp_awvalid && hp_awready) begin hp_awvalid <= 0; beat <= 0; hp_wdata <= buffer[0]; hp_wvalid <= 1; hp_wlast <= 0; st <= WR; end end
      WR:  if (hp_wvalid && hp_wready) begin
             if (beat == 15) begin hp_wvalid <= 0; hp_wlast <= 0; hp_bready <= 1; st <= BR; end
             else begin beat <= beat + 1; hp_wdata <= buffer[beat[3:0] + 4'd1]; hp_wlast <= (beat == 14); end
           end
      BR:  if (hp_bvalid && hp_bready) begin hp_bready <= 0; if (hp_bresp != 0) err <= 1; st <= NEXT; end
      NEXT: begin sa <= sa + 128; da <= da + 128; bytes_done <= bytes_done + 128;
              if (rem <= 128) begin rem <= 0; busy <= 0; done <= 1; st <= IDLE; end else begin rem <= rem - 128; st <= AR; end end
    endcase
    if (busy) cycles <= cycles + 1;
    start_d <= start_tog; clr_d <= clr_tog;
  end

  // ---- GP0 register slave ----
  wire do_wr = awvalid & wvalid & ~bvalid;
  wire do_rd = arvalid & ~rvalid;
  wire [7:0] wa = awaddr[9:2], ra = araddr[9:2];
  always @(posedge aclk) begin
    awready <= 0; wready <= 0; arready <= 0;
    if (do_wr && !awready) begin
      awready <= 1; wready <= 1; bvalid <= 1; bid <= awid;
      case (wa)
        8'h01: scratch <= wdata;
        8'h04: ledr <= wdata[3:0];
        8'h08: hdr_out0 <= wdata;   8'h09: hdr_out1 <= wdata[1:0];
        8'h0A: hdr_tri0 <= wdata;   8'h0B: hdr_tri1 <= wdata[1:0];
        8'h10: begin scl <= wdata[0]; sda_rel <= wdata[1]; end
        8'h14: oledr <= wdata[3:0];
        8'h18: begin prst <= wdata[0]; pmdc <= wdata[1]; pmdio_rel <= wdata[2]; end
        8'h1C: begin tm_en <= wdata[0]; tm_ien <= wdata[1]; end
        8'h1D: tm_period <= wdata;
        8'h1F: if (wdata[0]) tm_clr_tog <= ~tm_clr_tog;
        8'h42: src <= wdata;  8'h43: dst <= wdata;  8'h44: len <= wdata;
        8'h45: begin mode <= wdata[1]; irq_en <= wdata[3]; if (wdata[0] && !busy) start_tog <= ~start_tog; if (wdata[2]) clr_tog <= ~clr_tog; end
        default: ;
      endcase
    end
    if (bvalid && bready) bvalid <= 0;
    if (do_rd && !arready) begin
      arready <= 1; rvalid <= 1; rid <= arid;
      case (ra)
        8'h00: rdata <= 32'h5A4D4231;                     // "ZMB1"
        8'h01: rdata <= scratch;
        8'h02: rdata <= {31'b0, locked};
        8'h04: rdata <= {28'b0, ledr};
        8'h05: rdata <= {30'b0, ks1};
        8'h08: rdata <= hdr_out0;  8'h09: rdata <= {30'b0, hdr_out1};
        8'h0A: rdata <= hdr_tri0;  8'h0B: rdata <= {30'b0, hdr_tri1};
        8'h0C: rdata <= hin_s1[31:0]; 8'h0D: rdata <= {30'b0, hin_s1[33:32]};
        8'h10: rdata <= {30'b0, eeprom_sda, scl};
        8'h14: rdata <= {28'b0, oledr};
        8'h18: rdata <= {29'b0, pmdio_rel, pmdc, prst};
        8'h19: rdata <= {31'b0, phy_mdio};
        8'h1C: rdata <= {30'b0, tm_ien, tm_en};
        8'h1D: rdata <= tm_period;
        8'h1E: rdata <= tm_count;
        8'h1F: rdata <= {31'b0, tm_pend};
        8'h20: rdata <= d50;  8'h21: rdata <= d100; 8'h22: rdata <= d150; 8'h23: rdata <= d200; 8'h24: rdata <= df1; 8'h25: rdata <= df2;
        8'h26: rdata <= wcount;
        8'h42: rdata <= src;  8'h43: rdata <= dst;  8'h44: rdata <= len;
        8'h45: rdata <= {28'b0, irq_en, 1'b0, mode, 1'b0};
        8'h46: rdata <= {29'b0, err, done, busy};
        8'h47: rdata <= csum;  8'h48: rdata <= cycles;  8'h49: rdata <= bytes_done;
        default: rdata <= 32'hDEADBEEF;
      endcase
    end
    if (rvalid && rready) rvalid <= 0;
  end
endmodule

// counts cycles of clk during one window of 2^20 aclk cycles
module meter(input aclk, input clk, output reg [31:0] delta = 0);
  reg [19:0] w = 0; reg wt = 0;
  always @(posedge aclk) begin w <= w + 1; if (&w) wt <= ~wt; end
  reg [2:0] sy = 0; reg [31:0] cnt = 0, snap = 0;
  always @(posedge clk) begin
    cnt <= cnt + 1; sy <= {sy[1:0], wt};
    if (sy[2] != sy[1]) begin delta <= cnt - snap; snap <= cnt; end
  end
endmodule
