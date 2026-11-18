// Simulation testbench for ple_mac: transmit path (preamble/SFD/data/gap on the RGMII pins), receive path (edge-aligned RGMII like this PHY: captured on the inverted clock),
// raw frame capture incl. preamble, counters, truncation at 320 bytes, a frame arriving while the buffer is still full counts as missed.
`timescale 1ns/1ps
module tb_ple_mac;
  reg clk50 = 0; always #10 clk50 = ~clk50;
  reg [1:0] key = 2'b11; wire [3:0] led; wire phy_rst_n, phy_mdc, phy_mdio, rgmii_txc, rgmii_tx_ctl; wire [3:0] rgmii_txd;
  reg rgmii_rxc = 0, rgmii_rx_ctl = 0; reg [3:0] rgmii_rxd = 0;
  pullup (phy_mdio);
  ple_mac dut(.clk50(clk50), .key(key), .led(led), .phy_rst_n(phy_rst_n), .phy_mdc(phy_mdc), .phy_mdio(phy_mdio), .rgmii_txc(rgmii_txc), .rgmii_tx_ctl(rgmii_tx_ctl),
              .rgmii_txd(rgmii_txd), .rgmii_rxc(rgmii_rxc), .rgmii_rx_ctl(rgmii_rx_ctl), .rgmii_rxd(rgmii_rxd));
  integer fails = 0, checks = 0, i, j;
  task check(input [255:0] name, input [31:0] got, input [31:0] want);
    begin checks = checks + 1; if (got !== want) begin fails = fails + 1; $display("FAIL %0s: got %h want %h", name, got, want); end end
  endtask
  reg [31:0] v;
  // ---- TX monitor: low nibble on the rising TXC edge, high nibble on the falling edge ----
  reg [7:0] txcap [0:511]; integer txn = 0; reg [3:0] lo; reg capturing = 0;
  always @(posedge rgmii_txc) begin #2; lo = rgmii_txd; capturing = rgmii_tx_ctl; end            // the PHY samples in the middle of each half period
  always @(negedge rgmii_txc) begin #2; if (capturing) begin txcap[txn] = {rgmii_txd, lo}; txn = txn + 1; end end
  realtime t_last = 0, t_fall = 0; always @(negedge rgmii_txc) if (capturing) t_last = $realtime; always @(negedge dut.tx_busy) t_fall = $realtime;
  // ---- RX driver: PHY without clock delay, data changes with the clock edges (low nibble while RXC is high, high nibble while low) ----
  task rx_byte(input [7:0] b);
    begin rgmii_rxc = 1; #1; rgmii_rxd = b[3:0]; rgmii_rx_ctl = 1; #3; rgmii_rxc = 0; #1; rgmii_rxd = b[7:4]; rgmii_rx_ctl = 1; #3; end
  endtask
  task rx_idle(input integer n); integer k; begin for (k = 0; k < n; k = k + 1) begin rgmii_rxc = 1; #1; rgmii_rx_ctl = 0; rgmii_rxd = 4'h1; #3; rgmii_rxc = 0; #4; end end endtask
  task rx_frame(input integer len, input [7:0] seed);   // preamble + SFD + len payload bytes
    integer k;
    begin for (k = 0; k < 7; k = k + 1) rx_byte(8'h55); rx_byte(8'hD5); for (k = 0; k < len; k = k + 1) rx_byte(seed + k); rx_idle(6); end
  endtask
  task rd(input [31:0] a, output [31:0] d); begin dut.ps7.gp_read(a, d); end endtask
  initial begin
    rx_idle(4);
    #200;
    rd(32'h000, v); check("ID", v, 32'h4D414331);
    dut.ps7.gp_write(32'h004, 32'h0BADF00D); rd(32'h004, v); check("scratch", v, 32'h0BADF00D);
    dut.ps7.gp_write(32'h01C, 32'h1); check("phy reset released", phy_rst_n, 1);
    // --- transmit a 64-byte frame ---
    for (i = 0; i < 16; i = i + 1) dut.ps7.gp_write(32'h200 + 4 * i, {8'h40 + 8'd4 * i[7:0] + 8'd3, 8'h40 + 8'd4 * i[7:0] + 8'd2, 8'h40 + 8'd4 * i[7:0] + 8'd1, 8'h40 + 8'd4 * i[7:0]});
    dut.ps7.gp_write(32'h030, 64); dut.ps7.gp_write(32'h024, 1);
    repeat (400) @(posedge dut.aclk);
    check("tx bytes seen", txn, 7 + 1 + 64);
    for (i = 0; i < 7; i = i + 1) check("preamble", txcap[i], 8'h55);
    check("sfd", txcap[7], 8'hD5);
    for (i = 0; i < 64; i = i + 1) if (txcap[8 + i] !== 8'h40 + i[7:0]) begin fails = fails + 1; $display("FAIL tx data byte %0d: %h", i, txcap[8 + i]); i = 999; end
    check("inter-frame gap (16 clk125 cycles, measured 116 ns)", (t_fall - t_last >= 112.0 && t_fall - t_last <= 120.0), 1);
    rd(32'h038, v); check("frames_tx", v, 1); rd(32'h028, v); check("tx not busy", v[1], 0);
    // --- receive a 60-byte frame (raw capture includes preamble + SFD) ---
    rx_frame(60, 8'h10); rx_idle(80);
    rd(32'h028, v); check("rx_ready", v[0], 1); rd(32'h02C, v); check("rx_len", v, 8 + 60); rd(32'h034, v); check("frames_rx", v, 1);
    for (i = 0; i < 8; i = i + 1) begin rd(32'h400 + 4 * i, v); check("rx preamble/sfd", v[7:0], i < 7 ? 8'h55 : 8'hD5); end
    for (i = 0; i < 60; i = i + 1) begin rd(32'h400 + 4 * (8 + i), v); if (v[7:0] !== 8'h10 + i[7:0]) begin fails = fails + 1; $display("FAIL rx byte %0d: %h", i, v[7:0]); i = 999; end end
    // --- a second frame while the first is not acknowledged is counted as missed and does not overwrite ---
    rx_frame(40, 8'h80); rx_idle(80);
    rd(32'h03C, v); check("missed", v, 1); rd(32'h02C, v); check("rx_len unchanged", v, 8 + 60); rd(32'h400 + 4 * 8, v); check("buffer not overwritten", v[7:0], 8'h10);
    // --- acknowledge, then an oversized frame is truncated to 320 bytes ---
    dut.ps7.gp_write(32'h024, 2); rx_idle(60); rd(32'h028, v); check("rx_ready cleared by ack", v[0], 0);
    rx_frame(400, 8'h00); rx_idle(80);
    rd(32'h02C, v); check("long frame truncated", v, 320); rd(32'h034, v); check("frames_rx 2", v, 2);
    rd(32'h400 + 4 * 319, v); check("last stored byte", v[7:0], 8'd311);
    // --- counters clear ---
    dut.ps7.gp_write(32'h024, 4); rx_idle(60); rd(32'h034, v); check("frames_rx cleared", v, 0); rd(32'h03C, v); check("missed cleared", v, 0); rd(32'h038, v); check("frames_tx cleared", v, 0);
    $display("ple_mac testbench: %0d checks, %0d failures -> %0s", checks, fails, fails == 0 ? "PASS" : "FAIL");
    $finish;
  end
  initial begin #60000000; $display("TIMEOUT"); $finish; end
endmodule
