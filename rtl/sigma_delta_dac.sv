// Second-order CIFB, two integrators and one quantizer. Internal 6 dB
// headroom bounds the loop for all 16-bit PCM inputs (density 25%..75%).
// Linearized NTF = (1-z^-1)^2. Output requires an analog reconstruction LPF.
module sigma_delta_dac (
  input logic clk, rst,
  input logic [15:0] audio_unsigned,
  output logic dac_out
);
  logic signed [23:0] i1, i2, next_i1, next_i2, x, feedback;
  assign x=($signed({8'b0,audio_unsigned})-24'sd32768) >>> 1;
  assign feedback=dac_out?24'sd32768:-24'sd32768;
  assign next_i1=i1+x-feedback;
  assign next_i2=i2+next_i1-feedback;
  always_ff @(posedge clk) begin
    if(rst) begin i1<=0; i2<=0; dac_out<=0; end
    else begin i1<=next_i1; i2<=next_i2; dac_out<=~next_i2[23]; end
  end
endmodule
