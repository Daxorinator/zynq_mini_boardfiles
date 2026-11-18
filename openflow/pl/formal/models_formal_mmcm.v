// Formal stand-in for the MMCM: all outputs are free (any clock/lock behaviour must be handled by the design)
module MMCME2_BASE #(parameter real CLKIN1_PERIOD = 10.0, parameter real CLKFBOUT_MULT_F = 5.0, parameter integer DIVCLK_DIVIDE = 1, parameter real CLKOUT0_DIVIDE_F = 1.0,
                     parameter integer CLKOUT1_DIVIDE = 1, parameter integer CLKOUT2_DIVIDE = 1)
  (input CLKIN1, input CLKFBIN, input PWRDWN, input RST, output CLKFBOUT, output CLKFBOUTB, output CLKOUT0, output CLKOUT0B, output CLKOUT1, output CLKOUT1B,
   output CLKOUT2, output CLKOUT2B, output CLKOUT3, output CLKOUT3B, output CLKOUT4, output CLKOUT5, output CLKOUT6, output LOCKED);
  (* anyseq *) wire a, b, c, d, l;
  assign CLKFBOUT = a; assign CLKOUT0 = b; assign CLKOUT1 = c; assign CLKOUT2 = d; assign LOCKED = l;
  assign CLKFBOUTB = 0; assign CLKOUT0B = 0; assign CLKOUT1B = 0; assign CLKOUT2B = 0; assign CLKOUT3 = 0; assign CLKOUT3B = 0; assign CLKOUT4 = 0; assign CLKOUT5 = 0; assign CLKOUT6 = 0;
endmodule
