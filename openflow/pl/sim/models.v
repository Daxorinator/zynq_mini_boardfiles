`timescale 1ns/1ps
// Simulation models for the Xilinx primitives the open-flow designs instantiate (not synthesised; only for iverilog/Verilator-style simulation).
module BUFG(input I, output O); assign O = I; endmodule
module IBUF(input I, output O); assign O = I; endmodule

// Behavioural MMCME2_BASE: free-running output clocks from the VCO arithmetic (CLKIN period only used for the VCO rate), LOCKED after 100 input cycles.
module MMCME2_BASE #(parameter real CLKIN1_PERIOD = 10.0, parameter real CLKFBOUT_MULT_F = 5.0, parameter integer DIVCLK_DIVIDE = 1,
                     parameter real CLKOUT0_DIVIDE_F = 1.0, parameter integer CLKOUT1_DIVIDE = 1, parameter integer CLKOUT2_DIVIDE = 1,
                     parameter integer CLKOUT3_DIVIDE = 1, parameter integer CLKOUT4_DIVIDE = 1, parameter integer CLKOUT5_DIVIDE = 1, parameter integer CLKOUT6_DIVIDE = 1)
  (input CLKIN1, input CLKFBIN, input PWRDWN, input RST, output CLKFBOUT, output CLKFBOUTB, output reg CLKOUT0, output CLKOUT0B,
   output reg CLKOUT1, output CLKOUT1B, output reg CLKOUT2, output CLKOUT2B, output CLKOUT3, output CLKOUT3B, output CLKOUT4, output CLKOUT5, output CLKOUT6,
   output reg LOCKED);
  real vco_ns = CLKIN1_PERIOD * DIVCLK_DIVIDE / CLKFBOUT_MULT_F;     // VCO period in ns
  assign CLKFBOUT = CLKIN1; assign CLKFBOUTB = 0; assign CLKOUT0B = 0; assign CLKOUT1B = 0; assign CLKOUT2B = 0; assign CLKOUT3 = 0; assign CLKOUT3B = 0;
  assign CLKOUT4 = 0; assign CLKOUT5 = 0; assign CLKOUT6 = 0;
  initial begin CLKOUT0 = 0; CLKOUT1 = 0; CLKOUT2 = 0; LOCKED = 0; end
  always begin #(vco_ns * CLKOUT0_DIVIDE_F / 2.0) CLKOUT0 = ~CLKOUT0; end
  always begin #(vco_ns * CLKOUT1_DIVIDE   / 2.0) CLKOUT1 = ~CLKOUT1; end
  always begin #(vco_ns * CLKOUT2_DIVIDE   / 2.0) CLKOUT2 = ~CLKOUT2; end
  integer n = 0;
  always @(posedge CLKIN1) begin n = n + 1; if (n == 100) LOCKED = 1; end
endmodule

// Behavioural PS7 for the ports the open-flow designs use: FCLK0..2, an M_AXI_GP0 master driven from the testbench (tasks gp_write/gp_read),
// an S_AXI_HP0 slave in front of a memory (AXI3, 64-bit, 16-beat bursts, optional injected SLVERR), and IRQ_F2P[0] visible to the testbench.
module PS7(
  output [3:0] FCLKCLK, output [3:0] FCLKRESETN, input MAXIGP0ACLK, input SAXIHP0ACLK,
  output reg [31:0] MAXIGP0ARADDR, output reg MAXIGP0ARVALID, input MAXIGP0ARREADY, output [11:0] MAXIGP0ARID,
  output reg [31:0] MAXIGP0AWADDR, output reg MAXIGP0AWVALID, input MAXIGP0AWREADY, output [11:0] MAXIGP0AWID,
  output reg [31:0] MAXIGP0WDATA, output reg MAXIGP0WVALID, input MAXIGP0WREADY,
  input MAXIGP0BVALID, output reg MAXIGP0BREADY, input [11:0] MAXIGP0BID, input [1:0] MAXIGP0BRESP,
  input MAXIGP0RVALID, output reg MAXIGP0RREADY, input [11:0] MAXIGP0RID, input MAXIGP0RLAST, input [31:0] MAXIGP0RDATA, input [1:0] MAXIGP0RRESP,
  input [31:0] SAXIHP0ARADDR, input SAXIHP0ARVALID, output reg SAXIHP0ARREADY, input [1:0] SAXIHP0ARBURST, input [3:0] SAXIHP0ARLEN, input [1:0] SAXIHP0ARSIZE,
  input [5:0] SAXIHP0ARID, input [3:0] SAXIHP0ARCACHE, input [2:0] SAXIHP0ARPROT, input [1:0] SAXIHP0ARLOCK, input [3:0] SAXIHP0ARQOS,
  output reg [63:0] SAXIHP0RDATA, output reg SAXIHP0RVALID, input SAXIHP0RREADY, output reg SAXIHP0RLAST, output reg [1:0] SAXIHP0RRESP,
  input [31:0] SAXIHP0AWADDR, input SAXIHP0AWVALID, output reg SAXIHP0AWREADY, input [1:0] SAXIHP0AWBURST, input [3:0] SAXIHP0AWLEN, input [1:0] SAXIHP0AWSIZE,
  input [5:0] SAXIHP0AWID, input [3:0] SAXIHP0AWCACHE, input [2:0] SAXIHP0AWPROT, input [1:0] SAXIHP0AWLOCK, input [3:0] SAXIHP0AWQOS,
  input [63:0] SAXIHP0WDATA, input SAXIHP0WVALID, output reg SAXIHP0WREADY, input SAXIHP0WLAST, input [5:0] SAXIHP0WID, input [7:0] SAXIHP0WSTRB,
  output reg SAXIHP0BVALID, input SAXIHP0BREADY, output reg [1:0] SAXIHP0BRESP,
  input [19:0] IRQF2P);

  // clocks: FCLK0 100 MHz, FCLK1 50 MHz, FCLK2 75 MHz (the testbench may change these periods)
  real fclk0_half = 5.0, fclk1_half = 10.0, fclk2_half = 6.6666667;
  reg f0 = 0, f1 = 0, f2 = 0;
  always #(fclk0_half) f0 = ~f0;
  always #(fclk1_half) f1 = ~f1;
  always #(fclk2_half) f2 = ~f2;
  assign FCLKCLK = {1'b0, f2, f1, f0}; assign FCLKRESETN = 4'hF;
  assign MAXIGP0ARID = 12'h001; assign MAXIGP0AWID = 12'h001;
  wire irq0 = IRQF2P[0];

  // ---- HP0 memory ----
  reg [63:0] mem [0:65535];                       // 512 KiB, addressed by physical address modulo its size
  reg inject_hp_error = 0;                        // set by the testbench: read bursts answer SLVERR
  reg inject_hp_werror = 0;                       // write responses answer SLVERR
  integer protocol_errors = 0;                    // AXI rule violations seen by the model (WLAST position)
  integer hp_reads = 0, hp_writes = 0;
  function [15:0] widx(input [31:0] a); widx = a[18:3]; endfunction
  integer i;
  initial begin SAXIHP0ARREADY = 0; SAXIHP0RVALID = 0; SAXIHP0RLAST = 0; SAXIHP0RRESP = 0; SAXIHP0RDATA = 0; SAXIHP0AWREADY = 0; SAXIHP0WREADY = 0;
                SAXIHP0BVALID = 0; SAXIHP0BRESP = 0; for (i = 0; i < 65536; i = i + 1) mem[i] = 0; end
  reg [31:0] a; integer k;
  always @(posedge SAXIHP0ACLK) begin
    if (SAXIHP0ARVALID && !SAXIHP0ARREADY) begin                       // read burst: accept, then 16 beats
      a = SAXIHP0ARADDR; SAXIHP0ARREADY <= 1; @(posedge SAXIHP0ACLK); SAXIHP0ARREADY <= 0;
      for (k = 0; k < 16; k = k + 1) begin
        SAXIHP0RDATA <= mem[widx(a) + k]; SAXIHP0RRESP <= inject_hp_error ? 2'b10 : 2'b00; SAXIHP0RLAST <= (k == 15); SAXIHP0RVALID <= 1;
        @(posedge SAXIHP0ACLK); while (!SAXIHP0RREADY) @(posedge SAXIHP0ACLK);
      end
      SAXIHP0RVALID <= 0; SAXIHP0RLAST <= 0; hp_reads = hp_reads + 1;
    end else if (SAXIHP0AWVALID && !SAXIHP0AWREADY) begin             // write burst: accept the address, then 16 beats, then the response
      a = SAXIHP0AWADDR; SAXIHP0AWREADY <= 1; @(posedge SAXIHP0ACLK); SAXIHP0AWREADY <= 0;
      k = 0; SAXIHP0WREADY <= 1;
      while (k < 16) begin @(posedge SAXIHP0ACLK); if (SAXIHP0WVALID && SAXIHP0WREADY) begin mem[widx(a) + k] <= SAXIHP0WDATA; if (SAXIHP0WLAST !== (k == 15)) protocol_errors = protocol_errors + 1; k = k + 1; end end
      SAXIHP0WREADY <= 0; SAXIHP0BRESP <= inject_hp_werror ? 2'b10 : 2'b00; SAXIHP0BVALID <= 1;
      @(posedge SAXIHP0ACLK); while (!SAXIHP0BREADY) @(posedge SAXIHP0ACLK);
      SAXIHP0BVALID <= 0; hp_writes = hp_writes + 1;
    end
  end

  // ---- GP0 master tasks ----
  initial begin MAXIGP0ARVALID = 0; MAXIGP0AWVALID = 0; MAXIGP0WVALID = 0; MAXIGP0BREADY = 1; MAXIGP0RREADY = 1; MAXIGP0ARADDR = 0; MAXIGP0AWADDR = 0; MAXIGP0WDATA = 0; end
  task gp_write(input [31:0] addr, input [31:0] data);
    begin
      @(posedge MAXIGP0ACLK); MAXIGP0AWADDR <= addr; MAXIGP0WDATA <= data; MAXIGP0AWVALID <= 1; MAXIGP0WVALID <= 1;
      @(posedge MAXIGP0ACLK); while (!MAXIGP0AWREADY) @(posedge MAXIGP0ACLK);
      MAXIGP0AWVALID <= 0; MAXIGP0WVALID <= 0;
      while (!MAXIGP0BVALID) @(posedge MAXIGP0ACLK);
      @(posedge MAXIGP0ACLK);
    end
  endtask
  task gp_read(input [31:0] addr, output [31:0] data);
    begin
      @(posedge MAXIGP0ACLK); MAXIGP0ARADDR <= addr; MAXIGP0ARVALID <= 1;
      @(posedge MAXIGP0ACLK); while (!MAXIGP0ARREADY) @(posedge MAXIGP0ACLK);
      MAXIGP0ARVALID <= 0;
      while (!MAXIGP0RVALID) @(posedge MAXIGP0ACLK);
      data = MAXIGP0RDATA; @(posedge MAXIGP0ACLK);
    end
  endtask
  // irq wait helper (with timeout in aclk cycles); returns 1 if the interrupt line rose
  task wait_irq(input integer max_cycles, output ok);
    integer n;
    begin n = 0; while (!irq0 && n < max_cycles) begin @(posedge MAXIGP0ACLK); n = n + 1; end ok = irq0; end
  endtask
endmodule
