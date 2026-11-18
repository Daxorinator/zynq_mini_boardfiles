// Formal model of the PS7 ports hp_dma uses: it asserts the AXI3 master rules the design must obey on HP0 and assumes a legal AXI3 slave behind it.
// GP0 is left free (any legal-enough register traffic) so the proofs hold for whatever the CPU does, apart from the rules assumed below.
module PS7(
  output [3:0] FCLKCLK, output [3:0] FCLKRESETN, input MAXIGP0ACLK, input SAXIHP0ACLK,
  output [31:0] MAXIGP0ARADDR, output MAXIGP0ARVALID, input MAXIGP0ARREADY, output [11:0] MAXIGP0ARID,
  output [31:0] MAXIGP0AWADDR, output MAXIGP0AWVALID, input MAXIGP0AWREADY, output [11:0] MAXIGP0AWID,
  output [31:0] MAXIGP0WDATA, output MAXIGP0WVALID, input MAXIGP0WREADY,
  input MAXIGP0BVALID, output MAXIGP0BREADY, input [11:0] MAXIGP0BID, input [1:0] MAXIGP0BRESP,
  input MAXIGP0RVALID, output MAXIGP0RREADY, input [11:0] MAXIGP0RID, input MAXIGP0RLAST, input [31:0] MAXIGP0RDATA, input [1:0] MAXIGP0RRESP,
  input [31:0] SAXIHP0ARADDR, input SAXIHP0ARVALID, output SAXIHP0ARREADY, input [1:0] SAXIHP0ARBURST, input [3:0] SAXIHP0ARLEN, input [1:0] SAXIHP0ARSIZE,
  input [5:0] SAXIHP0ARID, input [3:0] SAXIHP0ARCACHE, input [2:0] SAXIHP0ARPROT, input [1:0] SAXIHP0ARLOCK, input [3:0] SAXIHP0ARQOS,
  output [63:0] SAXIHP0RDATA, output SAXIHP0RVALID, input SAXIHP0RREADY, output SAXIHP0RLAST, output [1:0] SAXIHP0RRESP,
  input [31:0] SAXIHP0AWADDR, input SAXIHP0AWVALID, output SAXIHP0AWREADY, input [1:0] SAXIHP0AWBURST, input [3:0] SAXIHP0AWLEN, input [1:0] SAXIHP0AWSIZE,
  input [5:0] SAXIHP0AWID, input [3:0] SAXIHP0AWCACHE, input [2:0] SAXIHP0AWPROT, input [1:0] SAXIHP0AWLOCK, input [3:0] SAXIHP0AWQOS,
  input [63:0] SAXIHP0WDATA, input SAXIHP0WVALID, output SAXIHP0WREADY, input SAXIHP0WLAST, input [5:0] SAXIHP0WID, input [7:0] SAXIHP0WSTRB,
  output SAXIHP0BVALID, input SAXIHP0BREADY, output [1:0] SAXIHP0BRESP,
  input [19:0] IRQF2P);
  (* anyseq *) wire [3:0] f_clk;
  assign FCLKCLK = f_clk; assign FCLKRESETN = 4'hF;
  // ---- GP0: a master issuing arbitrary single transfers, keeping valid stable until accepted (AXI rule) ----
  (* anyseq *) wire [31:0] g_araddr, g_awaddr, g_wdata; (* anyseq *) wire g_arv, g_awv, g_wv, g_bready, g_rready;
  reg arv_q = 0, awv_q = 0, wv_q = 0; reg [31:0] araddr_q = 0, awaddr_q = 0, wdata_q = 0;
  assign MAXIGP0ARVALID = arv_q ? 1'b1 : g_arv; assign MAXIGP0ARADDR = arv_q ? araddr_q : g_araddr;
  assign MAXIGP0AWVALID = awv_q ? 1'b1 : g_awv; assign MAXIGP0AWADDR = awv_q ? awaddr_q : g_awaddr;
  assign MAXIGP0WVALID  = wv_q  ? 1'b1 : g_wv;  assign MAXIGP0WDATA  = wv_q  ? wdata_q  : g_wdata;
  assign MAXIGP0BREADY = g_bready; assign MAXIGP0RREADY = g_rready; assign MAXIGP0ARID = 0; assign MAXIGP0AWID = 0;
  wire gclk = MAXIGP0ACLK;
  always @(posedge gclk) begin
    arv_q <= MAXIGP0ARVALID && !MAXIGP0ARREADY; araddr_q <= MAXIGP0ARADDR;
    awv_q <= MAXIGP0AWVALID && !MAXIGP0AWREADY; awaddr_q <= MAXIGP0AWADDR;
    wv_q  <= MAXIGP0WVALID  && !MAXIGP0WREADY;  wdata_q  <= MAXIGP0WDATA;
  end
  // ---- HP0 read channel: a legal slave. Free ready/data; RVALID only inside an accepted burst; RLAST on the 16th beat; stable until accepted ----
  (* anyseq *) wire s_arready, s_rv, s_awready, s_wready, s_bv; (* anyseq *) wire [63:0] s_rdata; (* anyseq *) wire [1:0] s_rresp, s_bresp;
  reg rbusy = 0; reg [4:0] rbeats = 0; reg rv_q = 0;
  assign SAXIHP0ARREADY = s_arready && !rbusy;                       // one outstanding read burst
  assign SAXIHP0RVALID = rbusy && (rv_q ? 1'b1 : s_rv);
  assign SAXIHP0RLAST = (rbeats == 15); assign SAXIHP0RDATA = s_rdata; assign SAXIHP0RRESP = s_rresp;
  always @(posedge SAXIHP0ACLK) begin
    rv_q <= SAXIHP0RVALID && !SAXIHP0RREADY;
    if (SAXIHP0ARVALID && SAXIHP0ARREADY) begin rbusy <= 1; rbeats <= 0; end
    if (SAXIHP0RVALID && SAXIHP0RREADY) begin rbeats <= rbeats + 1; if (rbeats == 15) rbusy <= 0; end
  end
  // ---- HP0 write channel: AW accepted, then exactly 16 W beats, then one B response (stable until accepted) ----
  reg wbusy = 0, wdone = 0, bv_q = 0, aw_seen = 0; reg [4:0] wbeats = 0;
  assign SAXIHP0AWREADY = s_awready && !wbusy && !wdone;
  assign SAXIHP0WREADY = wbusy && s_wready;
  assign SAXIHP0BVALID = wdone && (bv_q ? 1'b1 : s_bv); assign SAXIHP0BRESP = s_bresp;
  always @(posedge SAXIHP0ACLK) begin
    bv_q <= SAXIHP0BVALID && !SAXIHP0BREADY;
    if (SAXIHP0AWVALID && SAXIHP0AWREADY) begin wbusy <= 1; wbeats <= 0; end
    if (SAXIHP0WVALID && SAXIHP0WREADY) begin wbeats <= wbeats + 1; if (wbeats == 15) begin wbusy <= 0; wdone <= 1; end end
    if (SAXIHP0BVALID && SAXIHP0BREADY) wdone <= 0;
  end
  // ---- master rules the design must obey ----
  reg init = 1; always @(posedge SAXIHP0ACLK) init <= 0;
  reg arv_p = 0, awv_p = 0, wv_p = 0, arr_p = 0, awr_p = 0, wr_p = 0; reg [31:0] araddr_p, awaddr_p; reg [63:0] wdata_p; reg wlast_p;
  always @(posedge SAXIHP0ACLK) begin
    arv_p <= SAXIHP0ARVALID; arr_p <= SAXIHP0ARREADY; araddr_p <= SAXIHP0ARADDR;
    awv_p <= SAXIHP0AWVALID; awr_p <= SAXIHP0AWREADY; awaddr_p <= SAXIHP0AWADDR;
    wv_p <= SAXIHP0WVALID; wr_p <= SAXIHP0WREADY; wdata_p <= SAXIHP0WDATA; wlast_p <= SAXIHP0WLAST;
    if (!init) begin
      if (arv_p && !arr_p) begin assert(SAXIHP0ARVALID); assert(SAXIHP0ARADDR == araddr_p); end      // address held until accepted
      if (awv_p && !awr_p) begin assert(SAXIHP0AWVALID); assert(SAXIHP0AWADDR == awaddr_p); end
      if (wv_p && !wr_p) begin assert(SAXIHP0WVALID); assert(SAXIHP0WDATA == wdata_p); assert(SAXIHP0WLAST == wlast_p); end
    end

    if (SAXIHP0ARVALID) assert((SAXIHP0ARADDR[11:0] + 13'd128) <= 13'd4096);              // a burst must not cross a 4 KiB boundary
    if (SAXIHP0AWVALID) assert((SAXIHP0AWADDR[11:0] + 13'd128) <= 13'd4096);
    if (SAXIHP0WVALID && SAXIHP0WREADY) assert(SAXIHP0WLAST == (wbeats == 15));          // WLAST exactly on the 16th beat
  end
  // the engine drives W data only after its address was accepted
  always @(posedge SAXIHP0ACLK) if (SAXIHP0WVALID) assert(wbusy || (aw_seen));
  always @(posedge SAXIHP0ACLK) if (SAXIHP0AWVALID && SAXIHP0AWREADY) aw_seen <= 1; else if (SAXIHP0WVALID && SAXIHP0WREADY && wbeats == 15) aw_seen <= 0;
  always @(*) begin assume(SAXIHP0ARBURST == 2'b01 && SAXIHP0ARLEN == 4'd15 && SAXIHP0ARSIZE == 2'b11); end
endmodule
