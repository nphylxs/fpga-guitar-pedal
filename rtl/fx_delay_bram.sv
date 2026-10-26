module fx_delay_bram (
  input logic clk, rst, in_valid, enable,
  input logic signed [15:0] audio_in,
  input logic [15:0] delay_samples, // clamped to 1..32768
  input logic [7:0] feedback,       // gain = value/256, max 240/256
  output logic signed [15:0] audio_out,
  output logic out_valid
);
  import audio_math_pkg::*;
  (* ram_style="block" *) logic signed [15:0] mem [0:32767];
  logic [14:0] wr, read_addr;
  logic [15:0] filled, tap, bounded_delay;
  logic [7:0] fb;
  logic [3:0] state;
  logic active;
  logic signed [15:0] dry, rd, delayed;
  logic signed [31:0] damp_q8, damp_next;
  logic signed [40:0] feedback_product;
  logic signed [15:0] write_sample;
  assign bounded_delay=(delay_samples==0)?16'd1:
                       ((delay_samples>32768)?16'd32768:delay_samples);
  // alpha=1/4; Q8 state avoids a whole-sample feedback deadband.
  assign damp_next=damp_q8+((($signed(delayed)*32'sd256)-damp_q8) >>> 2);
  assign write_sample=sat16(48'(dry)+(48'(feedback_product) >>> 16));
  always_ff @(posedge clk) begin
    if(state==1) rd<=mem[read_addr];
    if(!rst && state==5) mem[wr]<=write_sample;
  end
  always_ff @(posedge clk) begin
    if(rst) begin
      state<=0; wr<=0; filled<=0; tap<=1; read_addr<=0; fb<=0;
      dry<=0; delayed<=0; damp_q8<=0; feedback_product<=0;
      audio_out<=0; out_valid<=0; active<=0;
    end else begin
      out_valid<=0;
      case(state)
        0: if(in_valid) begin
          dry<=audio_in; active<=enable; tap<=bounded_delay;
          read_addr<=wr-bounded_delay[14:0]; fb<=(feedback>240)?8'd240:feedback;
          state<=1;
        end
        1: state<=2;
        2: begin delayed<=(tap<=filled)?rd:16'sd0; state<=3; end
        3: begin damp_q8<=damp_next; state<=4; end
        4: begin feedback_product<=damp_q8*$signed({1'b0,fb}); state<=5; end
        5: begin
          audio_out<=active?sat16(48'(dry)+(48'(delayed) >>> 1)):dry;
          out_valid<=1; wr<=wr+1'b1;
          if(filled<32768) filled<=filled+1'b1;
          state<=0;
        end
        default: state<=0;
      endcase
    end
  end
endmodule
