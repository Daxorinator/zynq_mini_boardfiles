// Simulation testbench for hp_dma (standalone PL DMA through HP0): registers, copy, checksum-only, zero length, interrupt, bus errors, WLAST.
`timescale 1ns/1ps
module tb_hp_dma;
  reg clk50 = 0; always #10 clk50 = ~clk50;
  reg [1:0] key = 2'b11; wire [3:0] led;
  hp_dma dut(.clk50(clk50), .key(key), .led(led));
  integer fails = 0, checks = 0, i;
  task check(input [255:0] name, input [31:0] got, input [31:0] want);
    begin checks = checks + 1; if (got !== want) begin fails = fails + 1; $display("FAIL %0s: got %h want %h", name, got, want); end end
  endtask
  reg [31:0] v; reg ok;
  task dma(input [31:0] s, input [31:0] d, input [31:0] n, input [31:0] ctrl);
    begin dut.ps7.gp_write(32'h08, s); dut.ps7.gp_write(32'h0C, d); dut.ps7.gp_write(32'h10, n); dut.ps7.gp_write(32'h14, ctrl); end
  endtask
  task wait_done(output ok_);
    integer n; reg [31:0] st;
    begin ok_ = 0; for (n = 0; n < 4000 && !ok_; n = n + 1) begin dut.ps7.gp_read(32'h18, st); if (st[1]) ok_ = 1; end end
  endtask
  initial begin
    #200;
    dut.ps7.gp_read(32'h00, v); check("ID", v, 32'h48504431);
    dut.ps7.gp_write(32'h04, 32'h12345678); dut.ps7.gp_read(32'h04, v); check("scratch", v, 32'h12345678);
    for (i = 0; i < 2048; i = i + 1) dut.ps7.mem[(32'h0002_0000 >> 3) + i] = {32'h11110000 + i, ~(32'h22220000 + i)};
    dma(32'h0002_0000, 32'h0005_0000, 16384, 32'h9);                   // copy 16 KiB, irq enable
    dut.ps7.wait_irq(400000, ok); check("irq", ok, 1);
    wait_done(ok); check("done", ok, 1);
    dut.ps7.gp_read(32'h18, v); check("status", v, 2);
    dut.ps7.gp_read(32'h24, v); check("bytes", v, 16384);
    dut.ps7.gp_read(32'h20, v); check("cycles nonzero", v != 0, 1);
    for (i = 0; i < 2048; i = i + 1) if (dut.ps7.mem[(32'h0005_0000 >> 3) + i] !== dut.ps7.mem[(32'h0002_0000 >> 3) + i]) begin fails = fails + 1; $display("FAIL copy word %0d", i); i = 9999; end
    begin : cs reg [31:0] want; want = 0; for (i = 0; i < 2048; i = i + 1) want = want + dut.ps7.mem[(32'h0002_0000 >> 3) + i][31:0] + dut.ps7.mem[(32'h0002_0000 >> 3) + i][63:32];
      dut.ps7.gp_read(32'h1C, v); check("checksum", v, want); end
    dut.ps7.gp_write(32'h14, 32'h4); repeat (4) @(posedge dut.aclk); check("irq cleared", dut.ps7.irq0, 0);
    dut.ps7.mem[(32'h0007_0000 >> 3)] = 64'h77; dma(32'h0002_0000, 32'h0007_0000, 2048, 32'h3); wait_done(ok); check("csum-only done", ok, 1);
    check("csum-only wrote nothing", dut.ps7.mem[(32'h0007_0000 >> 3)] === 64'h77, 1);
    begin : zl integer r0; r0 = dut.ps7.hp_reads; dma(0, 0, 0, 32'h3); wait_done(ok); check("zero length done", ok, 1); check("zero length no bus reads", dut.ps7.hp_reads, r0); end
    dut.ps7.inject_hp_error = 1; dut.ps7.gp_write(32'h14, 32'h4); dma(32'h0002_0000, 32'h0005_0000, 128, 32'h1); wait_done(ok);
    dut.ps7.gp_read(32'h18, v); check("read error flagged", v[2], 1); dut.ps7.inject_hp_error = 0;
    dut.ps7.inject_hp_werror = 1; dut.ps7.gp_write(32'h14, 32'h4); dma(32'h0002_0000, 32'h0005_0000, 128, 32'h1); wait_done(ok);
    dut.ps7.gp_read(32'h18, v); check("write error flagged", v[2], 1); dut.ps7.inject_hp_werror = 0;
    check("no AXI protocol violations (WLAST)", dut.ps7.protocol_errors, 0);
    // LEDs follow {err, done, busy, key0}
    dut.ps7.gp_write(32'h14, 32'h4); repeat (4) @(posedge dut.aclk); check("led idle", led, 4'b0001);
    $display("hp_dma testbench: %0d checks, %0d failures -> %0s", checks, fails, fails == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #80000000; $display("TIMEOUT"); $finish; end
endmodule
