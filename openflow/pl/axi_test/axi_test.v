// PS<->PL AXI-lite test: M_AXI_GP0 (0x40000000) slave + bit-banged I2C pins + FCLK0 frequency meter
module axi_test(input clk50, input [1:0] key, output [3:0] led, output i2c_scl, inout i2c_sda);
  wire [3:0] fclk, frst;
  wire aclk;
  wire [31:0] araddr, awaddr, wdata;
  wire arvalid, awvalid, wvalid, bready, rready;
  wire [11:0] arid, awid;
  reg arready = 0, awready = 0, wready = 0, bvalid = 0, rvalid = 0;
  reg [11:0] bid = 0, rid = 0; reg [31:0] rdata = 0;

  PS7 ps7 (
    .FCLKCLK(fclk), .FCLKRESETN(frst),
    .MAXIGP0ACLK(aclk),
    .MAXIGP0ARADDR(araddr), .MAXIGP0ARVALID(arvalid), .MAXIGP0ARREADY(arready), .MAXIGP0ARID(arid),
    .MAXIGP0AWADDR(awaddr), .MAXIGP0AWVALID(awvalid), .MAXIGP0AWREADY(awready), .MAXIGP0AWID(awid),
    .MAXIGP0WDATA(wdata), .MAXIGP0WVALID(wvalid), .MAXIGP0WREADY(wready),
    .MAXIGP0BVALID(bvalid), .MAXIGP0BREADY(bready), .MAXIGP0BID(bid), .MAXIGP0BRESP(2'b00),
    .MAXIGP0RVALID(rvalid), .MAXIGP0RREADY(rready), .MAXIGP0RID(rid), .MAXIGP0RLAST(1'b1),
    .MAXIGP0RDATA(rdata), .MAXIGP0RRESP(2'b00));
  BUFG bufg_aclk (.I(fclk[0]), .O(aclk));

  // registers
  reg [31:0] scratch = 0; reg [3:0] ledr = 4'h0; reg scl = 1; reg sda_rel = 1;
  reg [31:0] fc = 0;                 // free-running FCLK0 counter
  reg [31:0] fdelta = 0, fsnap = 0;  // FCLK0 cycles per ~10.5 ms (2^19 clk50 cycles)
  reg [18:0] w50 = 0; reg wt = 0;
  always @(posedge clk50) begin w50 <= w50 + 1; if (&w50) wt <= ~wt; end
  reg [2:0] wsync = 0;
  reg [1:0] ksync0 = 2'b11, ksync1 = 2'b11;
  always @(posedge aclk) begin
    fc <= fc + 1;
    wsync <= {wsync[1:0], wt};
    if (wsync[2] != wsync[1]) begin fdelta <= fc - fsnap; fsnap <= fc; end
    ksync0 <= key; ksync1 <= ksync0;
  end

  assign i2c_scl = scl;
  assign i2c_sda = sda_rel ? 1'bz : 1'b0;
  assign led = ledr;

  wire do_wr = awvalid & wvalid & ~bvalid;
  wire do_rd = arvalid & ~rvalid;
  always @(posedge aclk) begin
    awready <= 0; wready <= 0; arready <= 0;
    if (do_wr && !awready) begin
      awready <= 1; wready <= 1; bvalid <= 1; bid <= awid;
      case (awaddr[7:2])
        6'h01: scratch <= wdata;
        6'h03: ledr <= wdata[3:0];
        6'h05: begin scl <= wdata[0]; sda_rel <= wdata[1]; end
        default: ;
      endcase
    end
    if (bvalid && bready) bvalid <= 0;
    if (do_rd && !arready) begin
      arready <= 1; rvalid <= 1; rid <= arid;
      case (araddr[7:2])
        6'h00: rdata <= 32'h4F584337;      // "OXC7"
        6'h01: rdata <= scratch;
        6'h02: rdata <= fc;
        6'h03: rdata <= {28'b0, ledr};
        6'h04: rdata <= {30'b0, ksync1};
        6'h05: rdata <= {30'b0, i2c_sda, scl};
        6'h06: rdata <= fdelta;
        default: rdata <= 32'hDEADBEEF;
      endcase
    end
    if (rvalid && rready) rvalid <= 0;
  end
endmodule
