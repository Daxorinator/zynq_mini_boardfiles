// Frequency meter: counts edges of six unrelated clocks over a gate of GATE reference-clock cycles
// (default 10,000,000 cycles = 100 ms at a 100 MHz reference). Each count is the number of edges of
// that clock in one gate, i.e. frequency in Hz / 10 at the default gate. Counts are exposed on plain
// 32-bit ports for AXI GPIO inputs, so no AXI slave logic is needed.
`timescale 1ns / 1ps

// Free-running counter in the measured clock's domain, handed to the reference domain as Gray code.
module fm_clk_counter (
    input  wire        clk,
    output reg  [31:0] gray = 32'd0
);
    reg [31:0] bin = 32'd0;
    always @(posedge clk) begin
        bin  <= bin + 32'd1;
        gray <= (bin + 32'd1) ^ ((bin + 32'd1) >> 1);
    end
endmodule

// One synchroniser + gate-edge capture in the reference domain.
module fm_capture (
    input  wire        ref_clk,
    input  wire        gate_end,
    input  wire [31:0] gray_in,
    output reg  [31:0] count = 32'd0
);
    (* ASYNC_REG = "TRUE" *) reg [31:0] sync0 = 32'd0;
    (* ASYNC_REG = "TRUE" *) reg [31:0] sync1 = 32'd0;
    reg [31:0] bin;
    reg [31:0] last = 32'd0;
    integer i;
    always @(posedge ref_clk) begin
        sync0 <= gray_in;
        sync1 <= sync0;
    end
    always @* begin                      // Gray -> binary
        bin[31] = sync1[31];
        for (i = 30; i >= 0; i = i - 1) bin[i] = bin[i+1] ^ sync1[i];
    end
    always @(posedge ref_clk) begin
        if (gate_end) begin
            count <= bin - last;
            last  <= bin;
        end
    end
endmodule

module freq_meter #(
    parameter GATE = 10000000
) (
    input  wire        ref_clk,
    input  wire        clk0, clk1, clk2, clk3, clk4, clk5,
    output wire [31:0] count0, count1, count2, count3, count4, count5,
    output reg  [31:0] gate_id = 32'd0
);
    reg [31:0] gate_cnt = 32'd0;
    reg        gate_end = 1'b0;
    always @(posedge ref_clk) begin
        if (gate_cnt == GATE - 1) begin
            gate_cnt <= 32'd0;
            gate_end <= 1'b1;
            gate_id  <= gate_id + 32'd1;
        end else begin
            gate_cnt <= gate_cnt + 32'd1;
            gate_end <= 1'b0;
        end
    end

    wire [31:0] g0, g1, g2, g3, g4, g5;
    fm_clk_counter u_c0 (.clk(clk0), .gray(g0));
    fm_clk_counter u_c1 (.clk(clk1), .gray(g1));
    fm_clk_counter u_c2 (.clk(clk2), .gray(g2));
    fm_clk_counter u_c3 (.clk(clk3), .gray(g3));
    fm_clk_counter u_c4 (.clk(clk4), .gray(g4));
    fm_clk_counter u_c5 (.clk(clk5), .gray(g5));
    fm_capture u_p0 (.ref_clk(ref_clk), .gate_end(gate_end), .gray_in(g0), .count(count0));
    fm_capture u_p1 (.ref_clk(ref_clk), .gate_end(gate_end), .gray_in(g1), .count(count1));
    fm_capture u_p2 (.ref_clk(ref_clk), .gate_end(gate_end), .gray_in(g2), .count(count2));
    fm_capture u_p3 (.ref_clk(ref_clk), .gate_end(gate_end), .gray_in(g3), .count(count3));
    fm_capture u_p4 (.ref_clk(ref_clk), .gate_end(gate_end), .gray_in(g4), .count(count4));
    fm_capture u_p5 (.ref_clk(ref_clk), .gate_end(gate_end), .gray_in(g5), .count(count5));
endmodule
