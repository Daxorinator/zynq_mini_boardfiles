// 640x480@~60 Hz DVI/HDMI test pattern transmitter for the ZYNQ MINI (no licensed IP).
// 50 MHz oscillator -> MMCM -> 25 MHz pixel clock and 125 MHz serial clock (5x, DDR 10:1 OSERDESE2).
// pattern: 0 = colour bars, 1 = horizontal gradient, 2 = checkerboard, 3 = solid white. enable gates the 5 V output switch.
`timescale 1ns / 1ps

module tmds_encoder (
    input  wire       clk,
    input  wire [7:0] d,
    input  wire [1:0] c,
    input  wire       de,
    output reg  [9:0] q = 10'b1101010100
);
    wire [3:0] n1d = d[0] + d[1] + d[2] + d[3] + d[4] + d[5] + d[6] + d[7];
    wire use_xnor = (n1d > 4'd4) || (n1d == 4'd4 && d[0] == 1'b0);
    wire [8:0] q_m;
    assign q_m[0] = d[0];
    assign q_m[1] = use_xnor ? ~(q_m[0] ^ d[1]) : (q_m[0] ^ d[1]);
    assign q_m[2] = use_xnor ? ~(q_m[1] ^ d[2]) : (q_m[1] ^ d[2]);
    assign q_m[3] = use_xnor ? ~(q_m[2] ^ d[3]) : (q_m[2] ^ d[3]);
    assign q_m[4] = use_xnor ? ~(q_m[3] ^ d[4]) : (q_m[3] ^ d[4]);
    assign q_m[5] = use_xnor ? ~(q_m[4] ^ d[5]) : (q_m[4] ^ d[5]);
    assign q_m[6] = use_xnor ? ~(q_m[5] ^ d[6]) : (q_m[5] ^ d[6]);
    assign q_m[7] = use_xnor ? ~(q_m[6] ^ d[7]) : (q_m[6] ^ d[7]);
    assign q_m[8] = ~use_xnor;

    wire [3:0] n1q = q_m[0] + q_m[1] + q_m[2] + q_m[3] + q_m[4] + q_m[5] + q_m[6] + q_m[7];
    wire [3:0] n0q = 4'd8 - n1q;
    reg signed [5:0] cnt = 6'sd0;                      // running disparity

    always @(posedge clk) begin
        if (de) begin
            if (cnt == 0 || n1q == n0q) begin
                q[9]   <= ~q_m[8];
                q[8]   <= q_m[8];
                q[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                if (q_m[8] == 1'b0) cnt <= cnt + $signed({2'b00, n0q}) - $signed({2'b00, n1q});
                else                cnt <= cnt + $signed({2'b00, n1q}) - $signed({2'b00, n0q});
            end else if ((cnt > 0 && n1q > n0q) || (cnt < 0 && n0q > n1q)) begin
                q[9]   <= 1'b1;
                q[8]   <= q_m[8];
                q[7:0] <= ~q_m[7:0];
                cnt    <= cnt + (q_m[8] ? 6'sd2 : 6'sd0) + $signed({2'b00, n0q}) - $signed({2'b00, n1q});
            end else begin
                q[9]   <= 1'b0;
                q[8]   <= q_m[8];
                q[7:0] <= q_m[7:0];
                cnt    <= cnt - (q_m[8] ? 6'sd0 : 6'sd2) + $signed({2'b00, n1q}) - $signed({2'b00, n0q});
            end
        end else begin
            cnt <= 6'sd0;
            case (c)
                2'b00:   q <= 10'b1101010100;
                2'b01:   q <= 10'b0010101011;
                2'b10:   q <= 10'b0101010100;
                default: q <= 10'b1010101011;
            endcase
        end
    end
endmodule

// One TMDS lane: 10 parallel bits at clkdiv -> serial at 2x clk5x (DDR), LSB first.
module tmds_lane (
    input  wire       clkdiv,
    input  wire       clk5x,
    input  wire       rst,
    input  wire [9:0] word,
    output wire       p,
    output wire       n
);
    wire ser, sh1, sh2;
    OSERDESE2 #(.DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"), .DATA_WIDTH(10), .SERDES_MODE("MASTER"),
                .TRISTATE_WIDTH(1), .INIT_OQ(1'b0), .SRVAL_OQ(1'b0)) master (
        .OQ(ser), .OFB(), .TQ(), .TFB(), .SHIFTOUT1(), .SHIFTOUT2(),
        .CLK(clk5x), .CLKDIV(clkdiv),
        .D1(word[0]), .D2(word[1]), .D3(word[2]), .D4(word[3]), .D5(word[4]), .D6(word[5]), .D7(word[6]), .D8(word[7]),
        .OCE(1'b1), .RST(rst), .SHIFTIN1(sh1), .SHIFTIN2(sh2),
        .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0), .TBYTEIN(1'b0), .TCE(1'b0), .TBYTEOUT());
    OSERDESE2 #(.DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"), .DATA_WIDTH(10), .SERDES_MODE("SLAVE"),
                .TRISTATE_WIDTH(1), .INIT_OQ(1'b0), .SRVAL_OQ(1'b0)) slave (
        .OQ(), .OFB(), .TQ(), .TFB(), .SHIFTOUT1(sh1), .SHIFTOUT2(sh2),
        .CLK(clk5x), .CLKDIV(clkdiv),
        .D1(1'b0), .D2(1'b0), .D3(word[8]), .D4(word[9]), .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0),
        .OCE(1'b1), .RST(rst), .SHIFTIN1(1'b0), .SHIFTIN2(1'b0),
        .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0), .TBYTEIN(1'b0), .TCE(1'b0), .TBYTEOUT());
    OBUFDS #(.IOSTANDARD("TMDS_33")) obuf (.I(ser), .O(p), .OB(n));
endmodule

module hdmi_tx (
    input  wire       clk50,
    input  wire       enable,
    input  wire [1:0] pattern,
    output wire       tmds_clk_p, tmds_clk_n,
    output wire [2:0] tmds_d_p, tmds_d_n,
    output wire       hdmi_oe,
    output wire       locked_led
);
    // ---- clocks ----
    wire clkfb, clkfb_b, c0, c1, c0b, pclk, clk5x, locked;
    MMCME2_BASE #(.CLKIN1_PERIOD(20.0), .CLKFBOUT_MULT_F(20.0), .DIVCLK_DIVIDE(1),
                  .CLKOUT0_DIVIDE_F(8.0), .CLKOUT1_DIVIDE(40)) mmcm (
        .CLKIN1(clk50), .CLKFBIN(clkfb_b), .CLKFBOUT(clkfb), .CLKOUT0(c0), .CLKOUT1(c1),
        .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0),
        .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6());
    BUFG bf (.I(clkfb), .O(clkfb_b));
    BUFG b5 (.I(c0), .O(clk5x));
    BUFG bp (.I(c1), .O(pclk));
    assign locked_led = locked;
    assign hdmi_oe = enable;

    // ---- timing: 640x480, 800x525 total, negative syncs ----
    reg [9:0] hc = 10'd0, vc = 10'd0;
    always @(posedge pclk) begin
        if (hc == 10'd799) begin
            hc <= 10'd0;
            vc <= (vc == 10'd524) ? 10'd0 : vc + 10'd1;
        end else hc <= hc + 10'd1;
    end
    wire de    = (hc < 10'd640) && (vc < 10'd480);
    wire hsync = ~((hc >= 10'd656) && (hc < 10'd752));
    wire vsync = ~((vc >= 10'd490) && (vc < 10'd492));

    // ---- test patterns ----
    reg [7:0] r, g, b;
    wire [2:0] bar = (hc < 10'd80)  ? 3'd0 : (hc < 10'd160) ? 3'd1 : (hc < 10'd240) ? 3'd2 : (hc < 10'd320) ? 3'd3 :
                     (hc < 10'd400) ? 3'd4 : (hc < 10'd480) ? 3'd5 : (hc < 10'd560) ? 3'd6 : 3'd7;
    wire [19:0] ramp_m = hc * 10'd205;                       // hc * 0.4 -> 0..255 across the line
    wire [7:0]  ramp   = ramp_m[16:9];
    always @(posedge pclk) begin
        case (pattern)
            2'd0: case (bar)                                    // white yellow cyan green magenta red blue black
                    3'd0: {r, g, b} <= 24'hFFFFFF;
                    3'd1: {r, g, b} <= 24'hFFFF00;
                    3'd2: {r, g, b} <= 24'h00FFFF;
                    3'd3: {r, g, b} <= 24'h00FF00;
                    3'd4: {r, g, b} <= 24'hFF00FF;
                    3'd5: {r, g, b} <= 24'hFF0000;
                    3'd6: {r, g, b} <= 24'h0000FF;
                    default: {r, g, b} <= 24'h000000;
                  endcase
            2'd1: {r, g, b} <= {ramp, ramp, ramp};                 // grey ramp
            2'd2: {r, g, b} <= (hc[5] ^ vc[5]) ? 24'hFFFFFF : 24'h000000;
            default: {r, g, b} <= 24'hFFFFFF;
        endcase
    end
    // pipeline stage for sync/de so they line up with the registered colour
    reg de_d, hs_d, vs_d;
    always @(posedge pclk) begin de_d <= de; hs_d <= hsync; vs_d <= vsync; end

    wire [9:0] tb, tg, tr;
    tmds_encoder eb (.clk(pclk), .d(b), .c({vs_d, hs_d}), .de(de_d), .q(tb));
    tmds_encoder eg (.clk(pclk), .d(g), .c(2'b00),        .de(de_d), .q(tg));
    tmds_encoder er (.clk(pclk), .d(r), .c(2'b00),        .de(de_d), .q(tr));

    wire rst = ~locked;
    tmds_lane l0 (.clkdiv(pclk), .clk5x(clk5x), .rst(rst), .word(tb), .p(tmds_d_p[0]), .n(tmds_d_n[0]));
    tmds_lane l1 (.clkdiv(pclk), .clk5x(clk5x), .rst(rst), .word(tg), .p(tmds_d_p[1]), .n(tmds_d_n[1]));
    tmds_lane l2 (.clkdiv(pclk), .clk5x(clk5x), .rst(rst), .word(tr), .p(tmds_d_p[2]), .n(tmds_d_n[2]));
    tmds_lane lc (.clkdiv(pclk), .clk5x(clk5x), .rst(rst), .word(10'b0000011111), .p(tmds_clk_p), .n(tmds_clk_n));
endmodule
