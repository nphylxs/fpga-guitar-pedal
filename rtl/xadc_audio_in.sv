// Rolling 16-conversion sum, coherent CDC cdc_payload, then audio-rate DC blocker.
module xadc_audio_in (
  input logic clk_xadc, rst_xadc, clk_100m, rst, sample_tick_en,
  input wire vauxp4, vauxn4,
  output logic signed [15:0] audio_out,
  output logic out_valid
);
  import audio_math_pkg::*;
  wire [15:0] adc_data;
  wire eoc, drdy;
  wire [15:0] vp = {11'b0,vauxp4,4'b0};
  wire [15:0] vn = {11'b0,vauxn4,4'b0};
  XADC #(.INIT_40(16'h0014), .INIT_41(16'h31ef),
         .INIT_42(16'h0400)) adc (
    .DCLK(clk_xadc), .RESET(rst_xadc), .DADDR(7'h14),
    .DEN(eoc), .DWE(1'b0), .DI(16'b0), .DO(adc_data), .DRDY(drdy),
    .EOC(eoc), .MUXADDR(), .EOS(), .BUSY(), .CHANNEL(), .ALM(), .OT(),
    .JTAGBUSY(), .JTAGLOCKED(), .JTAGMODIFIED(),
    .CONVST(1'b0), .CONVSTCLK(1'b0), .VP(1'b0), .VN(1'b0),
    .VAUXP(vp), .VAUXN(vn)
  );
  logic [11:0] history [0:15];
  logic [3:0] wr;
  logic [4:0] fill;
  logic [15:0] sum, next_sum;
  // Source payload remains fixed until destination acknowledges request.
  logic [15:0] cdc_payload;
  logic req, ack;
  (* ASYNC_REG="TRUE" *) logic [2:0] ack_sync, req_sync;
  logic [15:0] latest;
  logic have_sample;
  assign next_sum = sum - ((fill == 16) ? {4'b0,history[wr]} : 16'b0)
                          + {4'b0,adc_data[15:4]};
  always_ff @(posedge clk_xadc) begin
    if (rst_xadc) begin
      wr<=0; fill<=0; sum<=0; cdc_payload<=0; req<=0; ack_sync<=0;
    end else begin
      ack_sync <= {ack_sync[1:0],ack};
      if (drdy) begin
        history[wr]<=adc_data[15:4]; wr<=wr+1'b1; sum<=next_sum;
        if (fill<16) fill<=fill+1'b1;
        if (fill>=15 && req==ack_sync[2]) begin cdc_payload<=next_sum; req<=~req; end
      end
    end
  end
  // sum/4 is a 14-bit sample; shifting by 2 maps it to 16-bit PCM.
  // Equivalent to discarding the bottom two sum bits (retains 14 bits).
  logic signed [31:0] x_q8, previous_x, hp_q8, hp_delta;
  logic [1:0] hp_valid;
  logic signed [47:0] hp_product, hp_next;
  assign x_q8 = ($signed({16'b0,latest[15:2],2'b00}) - 32'sd32768) <<< 8;
  // Separate multiply, accumulation and output saturation at 100 MHz.
  assign hp_next = 48'(hp_delta) + (hp_product >>> 15);
  always_ff @(posedge clk_100m) begin
    if (rst) begin
      req_sync<=0; ack<=0; latest<=16'h8000; have_sample<=0;
      previous_x<=0; hp_q8<=0; audio_out<=0; out_valid<=0;
      hp_delta<=0; hp_product<=0; hp_valid<=0;
    end else begin
      req_sync<={req_sync[1:0],req}; out_valid<=0;
      if (req_sync[2]!=ack) begin latest<=cdc_payload; ack<=req_sync[2]; have_sample<=1; end
      hp_valid <= {hp_valid[0],sample_tick_en};
      if (sample_tick_en) begin
        if (have_sample) begin
          previous_x<=x_q8;
          hp_delta<=x_q8-previous_x;
          hp_product<=hp_q8 * 16'sd32604; // Q1.15: 0.9949951171875
        end else begin hp_delta<=0; hp_product<=0; end
      end
      if (hp_valid[0]) hp_q8<=hp_next[31:0];
      if (hp_valid[1]) begin
        audio_out<=sat16(48'(hp_q8) >>> 8);
        out_valid<=1;
      end
    end
  end
endmodule
