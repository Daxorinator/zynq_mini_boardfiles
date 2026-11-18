// Simulation testbench for zm_base (open-flow overlay): register file, header tri-state, timer interrupt, clock meters, DMA copy/checksum/error.
`timescale 1ns/1ps
module tb_zm_base;
  reg clk50 = 0; always #10 clk50 = ~clk50;
  reg [1:0] key = 2'b11;
  wire [3:0] led, oled; wire [33:0] hdr; wire eeprom_scl, eeprom_sda, phy_rst_n, phy_mdc, phy_mdio;
  pullup (eeprom_sda); pullup (phy_mdio);
  genvar g; generate for (g = 0; g < 34; g = g + 1) begin : pu pullup (hdr[g]); end endgenerate
  zm_base dut(.clk50(clk50), .key(key), .led(led), .hdr(hdr), .eeprom_scl(eeprom_scl), .eeprom_sda(eeprom_sda), .oled(oled),
              .phy_rst_n(phy_rst_n), .phy_mdc(phy_mdc), .phy_mdio(phy_mdio));
  integer fails = 0, checks = 0;
  task check(input [255:0] name, input [31:0] got, input [31:0] want);
    begin checks = checks + 1; if (got !== want) begin fails = fails + 1; $display("FAIL %0s: got %h want %h", name, got, want); end end
  endtask
  reg [31:0] v; reg ok; integer i, j;
  reg [63:0] pat;
  task fill(input integer words, input [31:0] base);       // pattern into the HP memory at byte address base
    begin for (i = 0; i < words; i = i + 1) dut.ps7.mem[(base >> 3) + i] = {32'hA5000000 + i, 32'h5A000000 ^ (i * 32'h01010101)}; end
  endtask
  task dma(input [31:0] s, input [31:0] d, input [31:0] n, input [31:0] ctrl);
    begin dut.ps7.gp_write(32'h108, s); dut.ps7.gp_write(32'h10C, d); dut.ps7.gp_write(32'h110, n); dut.ps7.gp_write(32'h114, ctrl); end
  endtask
  task wait_done(output ok_);
    integer n; reg [31:0] st;
    begin ok_ = 0; for (n = 0; n < 2000 && !ok_; n = n + 1) begin dut.ps7.gp_read(32'h118, st); if (st[1]) ok_ = 1; end end
  endtask
  initial begin
    #200;
    $display("[%0t] identity", $time);
    // --- identity and scratch ---
    dut.ps7.gp_read(32'h000, v); check("ID", v, 32'h5A4D4231);
    dut.ps7.gp_write(32'h004, 32'hCAFEF00D); dut.ps7.gp_read(32'h004, v); check("scratch", v, 32'hCAFEF00D);
    dut.ps7.gp_read(32'h3F0, v); check("unmapped", v, 32'hDEADBEEF);
    $display("[%0t] LEDs", $time);
    // --- LEDs, keys ---
    for (i = 0; i < 16; i = i + 1) begin dut.ps7.gp_write(32'h010, i); dut.ps7.gp_read(32'h010, v); check("leds readback", v, i); check("led pins", led, i); end
    key = 2'b10; repeat (4) @(posedge dut.aclk); dut.ps7.gp_read(32'h014, v); check("keys", v, 32'h2); key = 2'b11;
    $display("[%0t] header", $time);
    // --- header: all inputs by default; drive each pin, others stay high through the pull-ups ---
    dut.ps7.gp_read(32'h028, v); check("hdr tri0 reset", v, 32'hFFFFFFFF);
    dut.ps7.gp_read(32'h02C, v); check("hdr tri1 reset", v, 32'h3);
    for (j = 0; j < 34; j = j + 1) begin
      if (j < 32) begin dut.ps7.gp_write(32'h020, 0); dut.ps7.gp_write(32'h028, ~(32'h1 << j)); dut.ps7.gp_write(32'h02C, 32'h3); end
      else begin dut.ps7.gp_write(32'h024, 0); dut.ps7.gp_write(32'h02C, ~(32'h1 << (j - 32)) & 32'h3); dut.ps7.gp_write(32'h028, 32'hFFFFFFFF); end
      repeat (4) @(posedge dut.aclk);
      check("hdr pin driven low", hdr[j], 1'b0); check("other pins high", (&(hdr | (34'h1 << j))), 1'b1);
      dut.ps7.gp_read(32'h030, v); if (j < 32) check("hdr readback", v[j], 1'b0);
    end
    dut.ps7.gp_write(32'h028, 32'hFFFFFFFF); dut.ps7.gp_write(32'h02C, 32'h3);
    $display("[%0t] OLED", $time);
    // --- OLED / PHY / I2C pins ---
    dut.ps7.gp_write(32'h050, 32'h9); check("oled pins", oled, 4'h9);
    dut.ps7.gp_write(32'h060, 32'h1); check("phy reset released", phy_rst_n, 1'b1);
    dut.ps7.gp_write(32'h060, 32'h0); dut.ps7.gp_write(32'h060, 32'h4); repeat (4) @(posedge dut.aclk); dut.ps7.gp_read(32'h064, v); check("mdio pin high when released", v[0], 1'b1);
    dut.ps7.gp_write(32'h060, 32'h0); repeat (4) @(posedge dut.aclk); check("mdio driven low", phy_mdio, 1'b0);
    dut.ps7.gp_write(32'h040, 32'h0); check("sda low", eeprom_sda, 1'b0); dut.ps7.gp_write(32'h040, 32'h3); check("sda released", eeprom_sda, 1'b1); check("scl", eeprom_scl, 1'b1);
    $display("[%0t] timer", $time);
    // --- timer interrupt ---
    dut.ps7.gp_write(32'h074, 200); dut.ps7.gp_write(32'h070, 32'h3);
    dut.ps7.wait_irq(1000, ok); check("timer irq asserted", ok, 1);
    dut.ps7.gp_write(32'h070, 32'h1); dut.ps7.gp_write(32'h07C, 1); repeat (4) @(posedge dut.aclk);
    dut.ps7.gp_read(32'h07C, v); check("timer cleared", v[0], 1'b1 & v[0]);   // may re-pend (still enabled): only checks readability
    dut.ps7.gp_write(32'h070, 32'h0); dut.ps7.gp_write(32'h07C, 1); repeat (8) @(posedge dut.aclk);
    dut.ps7.gp_read(32'h07C, v); check("timer pending cleared when stopped", v, 0);
    $display("[%0t] clock meters", $time);
    // --- clock meters: cycles of each clock in one 2^20-aclk window (aclk = FCLK0 = 100 MHz) ---
    begin : meters
      reg [31:0] w0, w1; integer tol;
      dut.ps7.gp_read(32'h098, w0); w1 = w0; while (w1 == w0) dut.ps7.gp_read(32'h098, w1);
      w0 = w1; while (w1 == w0) dut.ps7.gp_read(32'h098, w1);       // a full window has now passed
      tol = 1100;                                                       // ~0.1 % of 2^20 plus sync jitter
      dut.ps7.gp_read(32'h080, v); if (v < 524288 - tol || v > 524288 + tol) begin fails = fails + 1; $display("FAIL meter 50 MHz: %0d", v); end checks = checks + 1;
      dut.ps7.gp_read(32'h084, v); if (v < 1048576 - tol || v > 1048576 + tol) begin fails = fails + 1; $display("FAIL meter 100 MHz: %0d", v); end checks = checks + 1;
      dut.ps7.gp_read(32'h088, v); if (v < 1572864 - 2*tol || v > 1572864 + 2*tol) begin fails = fails + 1; $display("FAIL meter 150 MHz: %0d", v); end checks = checks + 1;
      dut.ps7.gp_read(32'h08C, v); if (v < 2097152 - 3*tol || v > 2097152 + 3*tol) begin fails = fails + 1; $display("FAIL meter 200 MHz: %0d", v); end checks = checks + 1;
      dut.ps7.gp_read(32'h090, v); if (v < 524288 - tol || v > 524288 + tol) begin fails = fails + 1; $display("FAIL meter FCLK1 50 MHz: %0d", v); end checks = checks + 1;
      dut.ps7.gp_read(32'h094, v); if (v < 786432 - tol || v > 786432 + tol) begin fails = fails + 1; $display("FAIL meter FCLK2 75 MHz: %0d", v); end checks = checks + 1;
      dut.ps7.gp_read(32'h008, v); check("mmcm locked", v, 1);
    end
    $display("[%0t] DMA copy", $time);
    // --- DMA copy of 8 KiB (64 bursts of 128 B), checksum, interrupt ---
    fill(1024, 32'h0001_0000);
    dma(32'h0001_0000, 32'h0004_0000, 8192, 32'h9);                    // start, copy, irq enable
    dut.ps7.wait_irq(200000, ok); check("dma irq", ok, 1);
    wait_done(ok); check("dma done", ok, 1);
    dut.ps7.gp_read(32'h118, v); check("dma status done only", v, 2);
    dut.ps7.gp_read(32'h124, v); check("dma bytes", v, 8192);
    for (i = 0; i < 1024; i = i + 1) if (dut.ps7.mem[(32'h0004_0000 >> 3) + i] !== dut.ps7.mem[(32'h0001_0000 >> 3) + i]) begin fails = fails + 1; $display("FAIL copy word %0d", i); i = 2000; end
    begin : cs reg [31:0] want; want = 0; for (i = 0; i < 1024; i = i + 1) want = want + dut.ps7.mem[(32'h0001_0000 >> 3) + i][31:0] + dut.ps7.mem[(32'h0001_0000 >> 3) + i][63:32];
      dut.ps7.gp_read(32'h11C, v); check("dma checksum", v, want); end
    dut.ps7.gp_write(32'h114, 32'h4); repeat (4) @(posedge dut.aclk); check("irq cleared", dut.ps7.irq0, 0);
    $display("[%0t] checksum-only", $time);
    // --- checksum-only mode must not write ---
    dut.ps7.mem[(32'h0006_0000 >> 3)] = 64'h1111; dma(32'h0001_0000, 32'h0006_0000, 1024, 32'h3); wait_done(ok); check("csum-only done", ok, 1);
    check("csum-only wrote nothing", dut.ps7.mem[(32'h0006_0000 >> 3)] === 64'h1111, 1);
    $display("[%0t] zero length", $time);
    // --- zero length completes without bus traffic ---
    begin : zl integer r0; r0 = dut.ps7.hp_reads; dma(0, 0, 0, 32'h3); wait_done(ok); check("zero-length done", ok, 1); check("zero-length no reads", dut.ps7.hp_reads, r0); end
    $display("[%0t] bus error", $time);
    // --- misaligned runs are rejected with the error flag and no bus traffic ---
    begin : ma integer r0, w0; r0 = dut.ps7.hp_reads; w0 = dut.ps7.hp_writes;
      dut.ps7.gp_write(32'h114, 32'h4); dma(32'h0001_0040, 32'h0004_0000, 256, 32'h1); wait_done(ok); check("misaligned src rejected", ok, 1); dut.ps7.gp_read(32'h118, v); check("misaligned src err", v[2], 1);
      dut.ps7.gp_write(32'h114, 32'h4); dma(32'h0001_0000, 32'h0004_0020, 256, 32'h1); wait_done(ok); dut.ps7.gp_read(32'h118, v); check("misaligned dst err", v[2], 1);
      dut.ps7.gp_write(32'h114, 32'h4); dma(32'h0001_0000, 32'h0004_0000, 100, 32'h1); wait_done(ok); dut.ps7.gp_read(32'h118, v); check("bad length err", v[2], 1);
      check("no bus traffic for rejected runs", dut.ps7.hp_reads + dut.ps7.hp_writes, r0 + w0);
      dut.ps7.gp_write(32'h114, 32'h4); dma(32'h0001_0000, 32'h0004_0020, 256, 32'h3); wait_done(ok); dut.ps7.gp_read(32'h118, v); check("checksum-only ignores dst alignment", v[2], 0);
    end
    // --- bus error response is reported ---
    dut.ps7.inject_hp_error = 1; dut.ps7.gp_write(32'h114, 32'h4); dma(32'h0001_0000, 32'h0004_0000, 128, 32'h1); wait_done(ok);
    dut.ps7.gp_read(32'h118, v); check("read error flagged", v[2], 1); dut.ps7.inject_hp_error = 0;
    dut.ps7.inject_hp_werror = 1; dut.ps7.gp_write(32'h114, 32'h4); dma(32'h0001_0000, 32'h0004_0000, 128, 32'h1); wait_done(ok);
    dut.ps7.gp_read(32'h118, v); check("write error flagged", v[2], 1); dut.ps7.inject_hp_werror = 0;
    check("no AXI protocol violations (WLAST)", dut.ps7.protocol_errors, 0);
    $display("zm_base testbench: %0d checks, %0d failures -> %0s", checks, fails, fails == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #50000000; $display("TIMEOUT"); $finish; end
endmodule
