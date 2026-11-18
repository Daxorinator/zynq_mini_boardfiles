// Wrapper around hp_dma for the formal proofs: asserts on what the design shows on its LEDs (done and busy never both set).
module formal_hp_dma(input clk50, input [1:0] key, output [3:0] led);
  hp_dma dut(.clk50(clk50), .key(key), .led(led));
  always @(*) assert(!(led[2] && led[1]));
  always @(*) cover(led[2] && !led[3]);                   // a run can finish without error
  always @(*) cover(led[3]);                              // an error can be flagged
endmodule
