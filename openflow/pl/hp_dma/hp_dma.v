// PS+PL cooperation test: a PL block that copies (or just checksums) a buffer in DDR through the PS's AXI3 high-performance
// port HP0 (64-bit master), configured from Linux over M_AXI_GP0 (0x40000000), completion flagged in a status register
// and on IRQ_F2P[0].
//   0x00 ID ("HPD1")      0x04 scratch        0x08 SRC (physical)   0x0C DST (physical)   0x10 LEN in bytes (multiple of 128)
//   0x14 CTRL  W: bit0 start, bit1 mode (0 copy, 1 checksum only), bit2 clear done/irq, bit3 irq enable      R: {mode, irq_en}
//   0x18 STATUS bit0 busy, bit1 done, bit2 error (bad AXI response)
//   0x1C CHECKSUM (sum of all 32-bit words read)   0x20 CYCLES of the last run   0x24 BYTES done
module hp_dma(input clk50, input [1:0] key, output [3:0] led);
  wire [3:0] fclk, frst; wire aclk;
  // ---- GP0 (control) ----
  wire [31:0] araddr, awaddr, wdata; wire arvalid, awvalid, wvalid, bready, rready;
  wire [11:0] arid, awid;
  reg arready = 0, awready = 0, wready = 0, bvalid = 0, rvalid = 0;
  reg [11:0] bid = 0, rid = 0; reg [31:0] rdata = 0;
  // ---- HP0 (DDR master) ----
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

  // ---- DMA engine ----
  reg [31:0] src = 0, dst = 0, len = 0, rem = 0, sa = 0, da = 0, csum = 0, cycles = 0, bytes_done = 0;
  reg mode = 0, irq_en = 0, busy = 0, done = 0, err = 0;
  reg start_tog = 0, clr_tog = 0, start_d = 0, clr_d = 0;     // request flags toggled by the register slave (single driver each)
  wire start = start_tog ^ start_d, clr = clr_tog ^ clr_d;
  reg [63:0] buffer [0:15];
  reg [4:0] beat = 0;
  localparam IDLE = 0, AR = 1, RD = 2, AW = 3, WR = 4, BR = 5, NEXT = 6;
  reg [2:0] st = IDLE;
  assign irq = done & irq_en;
  assign led = {err, done, busy, key[0]};
  always @(posedge aclk) begin
    if (clr) begin done <= 0; err <= 0; end
    case (st)
      IDLE: if (start) begin
              busy <= 1; done <= 0; err <= 0; rem <= len; sa <= src; da <= dst; csum <= 0; cycles <= 0; bytes_done <= 0;
              st <= (len == 0) ? NEXT : AR;
            end
      AR:  begin hp_araddr <= sa; hp_arvalid <= 1; if (hp_arvalid && hp_arready) begin hp_arvalid <= 0; hp_rready <= 1; beat <= 0; st <= RD; end end
      RD:  begin
             if (hp_rvalid && hp_rready) begin
               buffer[beat[3:0]] <= hp_rdata; beat <= beat + 1;
               csum <= csum + hp_rdata[31:0] + hp_rdata[63:32];
               if (hp_rresp != 0) err <= 1;
               if (hp_rlast) begin hp_rready <= 0; st <= mode ? NEXT : AW; end
             end
           end
      AW:  begin hp_awaddr <= da; hp_awvalid <= 1; if (hp_awvalid && hp_awready) begin hp_awvalid <= 0; beat <= 0; hp_wdata <= buffer[0]; hp_wvalid <= 1; hp_wlast <= 0; st <= WR; end end
      WR:  if (hp_wvalid && hp_wready) begin
             if (beat == 15) begin hp_wvalid <= 0; hp_wlast <= 0; hp_bready <= 1; st <= BR; end
             else begin beat <= beat + 1; hp_wdata <= buffer[beat[3:0] + 4'd1]; hp_wlast <= (beat == 14); end
           end
      BR:  if (hp_bvalid && hp_bready) begin hp_bready <= 0; if (hp_bresp != 0) err <= 1; st <= NEXT; end
      NEXT: begin
              sa <= sa + 128; da <= da + 128; bytes_done <= bytes_done + 128;
              if (rem <= 128) begin rem <= 0; busy <= 0; done <= 1; st <= IDLE; end
              else begin rem <= rem - 128; st <= AR; end
            end
    endcase
    if (busy) cycles <= cycles + 1;
    start_d <= start_tog; clr_d <= clr_tog;
  end

  // ---- GP0 register slave ----
  reg [31:0] scratch = 0;
  wire do_wr = awvalid & wvalid & ~bvalid;
  wire do_rd = arvalid & ~rvalid;
  always @(posedge aclk) begin
    awready <= 0; wready <= 0; arready <= 0;
    if (do_wr && !awready) begin
      awready <= 1; wready <= 1; bvalid <= 1; bid <= awid;
      case (awaddr[7:2])
        6'h01: scratch <= wdata;
        6'h02: src <= wdata;
        6'h03: dst <= wdata;
        6'h04: len <= wdata;
        6'h05: begin mode <= wdata[1]; irq_en <= wdata[3]; if (wdata[0] && !busy) start_tog <= ~start_tog; if (wdata[2]) clr_tog <= ~clr_tog; end
        default: ;
      endcase
    end
    if (bvalid && bready) bvalid <= 0;
    if (do_rd && !arready) begin
      arready <= 1; rvalid <= 1; rid <= arid;
      case (araddr[7:2])
        6'h00: rdata <= 32'h48504431;           // "HPD1"
        6'h01: rdata <= scratch;
        6'h02: rdata <= src;
        6'h03: rdata <= dst;
        6'h04: rdata <= len;
        6'h05: rdata <= {28'b0, irq_en, 1'b0, mode, 1'b0};
        6'h06: rdata <= {29'b0, err, done, busy};
        6'h07: rdata <= csum;
        6'h08: rdata <= cycles;
        6'h09: rdata <= bytes_done;
        default: rdata <= 32'hDEADBEEF;
      endcase
    end
    if (rvalid && rready) rvalid <= 0;
  end
endmodule
