// formal stand-ins for the DDR primitives and the input buffer used by ple_mac: outputs are free
module ODDR #(parameter DDR_CLK_EDGE = "SAME_EDGE") (output Q, input C, input CE, input D1, input D2, input R, input S);
  (* anyseq *) wire q; assign Q = q;
endmodule
module IDDR #(parameter DDR_CLK_EDGE = "SAME_EDGE_PIPELINED") (output Q1, output Q2, input C, input CE, input D, input R, input S);
  (* anyseq *) wire q1, q2; assign Q1 = q1; assign Q2 = q2;
endmodule
module IBUF(input I, output O); assign O = I; endmodule
