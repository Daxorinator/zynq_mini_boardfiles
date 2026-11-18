module oled(input clk, input [1:0] key, output [3:0] led,
            output reg oled_sclk, output reg oled_mosi, output reg oled_dc, output reg oled_res);
  (* keep *) PS7 ps7 ();
  reg [7:0] fb [0:1023];
  initial $readmemh("fb.hex", fb);
  reg [7:0] q; reg [10:0] idx = 0;
  always @(posedge clk) q <= fb[idx[9:0]];

  function [7:0] initrom(input [4:0] i);
    case (i)
      0:initrom=8'hAE; 1:initrom=8'hD5; 2:initrom=8'h80; 3:initrom=8'hA8; 4:initrom=8'h3F; 5:initrom=8'hD3;
      6:initrom=8'h00; 7:initrom=8'h40; 8:initrom=8'h8D; 9:initrom=8'h14; 10:initrom=8'h20; 11:initrom=8'h00;
      12:initrom=8'hA1; 13:initrom=8'hC8; 14:initrom=8'hDA; 15:initrom=8'h12; 16:initrom=8'h81; 17:initrom=8'hCF;
      18:initrom=8'hD9; 19:initrom=8'hF1; 20:initrom=8'hDB; 21:initrom=8'h40; 22:initrom=8'hA4; 23:initrom=8'hA6;
      default:initrom=8'hAF;
    endcase
  endfunction
  function [7:0] winrom(input [2:0] i, input inv);
    case (i)
      0:winrom=8'h21; 1:winrom=8'h00; 2:winrom=8'h7F; 3:winrom=8'h22; 4:winrom=8'h00; 5:winrom=8'h07;
      default:winrom = inv ? 8'hA7 : 8'hA6;
    endcase
  endfunction

  reg [2:0] div = 0; wire ce = &div;
  reg [1:0] boot = 0, ph = 0;
  reg [20:0] wt = 21'h1FFFFF;
  reg busy = 0, half = 0; reg [2:0] bitn = 0; reg [7:0] sh = 0;
  reg [25:0] hb = 0;
  initial begin oled_sclk=0; oled_mosi=0; oled_dc=0; oled_res=0; end
  always @(posedge clk) begin
    div <= div + 1; hb <= hb + 1;
    if (ce) begin
      if (wt != 0) wt <= wt - 1;
      else if (boot == 0) begin oled_res <= 1; boot <= 1; wt <= 21'h1FFFFF; end
      else if (boot == 1) begin boot <= 2; end
      else if (!busy) begin
        busy <= 1; half <= 0; bitn <= 0;
        case (ph)
          0: begin sh <= initrom(idx[4:0]); oled_dc <= 0;
               if (idx == 24) begin ph <= 1; idx <= 0; end else idx <= idx + 1; end
          1: begin sh <= winrom(idx[2:0], ~key[0]); oled_dc <= 0;
               if (idx == 6) begin ph <= 2; idx <= 0; end else idx <= idx + 1; end
          default: begin sh <= q; oled_dc <= 1;
               if (idx == 1023) begin ph <= 1; idx <= 0; end else idx <= idx + 1; end
        endcase
      end else if (!half) begin oled_mosi <= sh[7]; oled_sclk <= 0; half <= 1; end
      else begin oled_sclk <= 1; sh <= {sh[6:0],1'b0}; half <= 0; bitn <= bitn + 1;
        if (bitn == 7) busy <= 0; end
    end
  end
  assign led = {oled_res, ~key[1], ~key[0], hb[25]};
endmodule
