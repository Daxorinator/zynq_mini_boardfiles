module blinky_ps7(input clk, input [1:0] key, output [3:0] led);
  // PS7 instantiated so its PL-facing inputs are pre-placed and tied off (nextpnr ties undriven PS7 inputs to GND)
  (* keep *) PS7 ps7 ();
  reg [27:0] c = 0;
  always @(posedge clk) c <= c + 1;
  assign led = (key != 2'b11) ? 4'hF : ~c[27:24];
endmodule
