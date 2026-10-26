module cmod_a7_guitar_top (
  input wire sysclk,
  input wire [1:0] btn,
  input wire vauxp4, vauxn4, uart_rx,
  output wire dac_pwm_out,
  output logic [1:0] led,
  output logic led0_r, led0_g, led0_b
);
  wire clk_in, clk_100m, clk_xadc, raw100, raw104;
  wire fb100, fb104, fb100_buf, fb104_buf, lock100, lock104;
  IBUF input_clock (.I(sysclk),.O(clk_in));
  // Two legal VCOs: 600 MHz and 624 MHz. One MMCM cannot produce this pair.
  MMCME2_BASE #(.CLKIN1_PERIOD(83.333333),.CLKFBOUT_MULT_F(50.0),
    .DIVCLK_DIVIDE(1),.CLKOUT0_DIVIDE_F(6.0)) mmcm100 (
    .CLKIN1(clk_in),.CLKFBIN(fb100_buf),.CLKFBOUT(fb100),.CLKOUT0(raw100),
    .LOCKED(lock100),.RST(1'b0),.PWRDWN(1'b0),
    .CLKFBOUTB(),.CLKOUT0B(),.CLKOUT1(),.CLKOUT1B(),.CLKOUT2(),.CLKOUT2B(),
    .CLKOUT3(),.CLKOUT3B(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6());
  MMCME2_BASE #(.CLKIN1_PERIOD(83.333333),.CLKFBOUT_MULT_F(52.0),
    .DIVCLK_DIVIDE(1),.CLKOUT0_DIVIDE_F(6.0)) mmcm104 (
    .CLKIN1(clk_in),.CLKFBIN(fb104_buf),.CLKFBOUT(fb104),.CLKOUT0(raw104),
    .LOCKED(lock104),.RST(1'b0),.PWRDWN(1'b0),
    .CLKFBOUTB(),.CLKOUT0B(),.CLKOUT1(),.CLKOUT1B(),.CLKOUT2(),.CLKOUT2B(),
    .CLKOUT3(),.CLKOUT3B(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6());
  BUFG b100(.I(raw100),.O(clk_100m));
  BUFG b104(.I(raw104),.O(clk_xadc));
  BUFG f100(.I(fb100),.O(fb100_buf));
  BUFG f104(.I(fb104),.O(fb104_buf));
  wire clocks_locked=lock100 & lock104;
  (* ASYNC_REG="TRUE" *) logic [2:0] por_pipe=0;
  always_ff @(posedge clk_100m or negedge clocks_locked)
    if(!clocks_locked) por_pipe<=0; else por_pipe<={por_pipe[1:0],1'b1};
  wire por=~por_pipe[2];
  logic reset_button, mode_button, mode_previous;
  pedal_debounce db0(.clk(clk_100m),.rst(por),.button(btn[0]),.level(reset_button));
  pedal_debounce db1(.clk(clk_100m),.rst(por),.button(btn[1]),.level(mode_button));
  // Synchronous reset distribution prevents async RAM control transitions.
  logic rst=1'b1;
  always_ff @(posedge clk_100m) rst<=por | reset_button;
  // Button does not reset its own debouncer or MMCMs.
  (* ASYNC_REG="TRUE" *) logic [2:0] xr_pipe=3'b111;
  always_ff @(posedge clk_xadc or posedge rst)
    if(rst) xr_pipe<=3'b111; else xr_pipe<={xr_pipe[1:0],1'b0};
  wire rst_xadc=xr_pipe[2];
  logic [10:0] tick_count;
  wire sample_tick_en=(tick_count==11'd2047);
  logic [2:0] mode, frame_mode;
  always_ff @(posedge clk_100m) begin
    if(rst) begin tick_count<=0; mode<=0; mode_previous<=0; frame_mode<=0; end
    else begin
      tick_count<=tick_count+1'b1;
      mode_previous<=mode_button;
      if(mode_button && !mode_previous) mode<=(mode==4)?3'd0:mode+1'b1;
      if(sample_tick_en) frame_mode<=mode;
    end
  end
  always_comb begin
    led=mode[1:0];
    // Common-anode RGB LED, active low. White/Red/Cyan/Blue/Magenta.
    case(mode)
      0: {led0_r,led0_g,led0_b}=3'b000;
      1: {led0_r,led0_g,led0_b}=3'b011;
      2: {led0_r,led0_g,led0_b}=3'b100;
      3: {led0_r,led0_g,led0_b}=3'b110;
      default: {led0_r,led0_g,led0_b}=3'b010;
    endcase
  end
  logic [7:0] drive, tone, depth, delay_time, feedback;
  logic [7:0] frame_drive, frame_depth, frame_feedback;
  logic [15:0] frame_alpha, frame_delay;
  uart_param_ctrl ctrl(.clk(clk_100m),.rst(rst),.uart_rx(uart_rx),
    .drive(drive),.tone(tone),.chorus_depth(depth),.delay_time(delay_time),.feedback(feedback));
  always_ff @(posedge clk_100m) begin
    if(rst) begin frame_drive<=48; frame_depth<=100; frame_feedback<=128;
      frame_alpha<=11264; frame_delay<=18304; end
    else if(sample_tick_en) begin
      frame_drive<=drive; frame_depth<=depth; frame_feedback<=feedback;
      frame_alpha<=16'd512+({8'b0,tone}*16'd112);
      frame_delay<=16'd128+({8'b0,delay_time} << 7);
    end
  end
  logic signed [15:0] adc_audio, od_audio, chorus_audio, delay_audio, audio_out;
  logic adc_valid, od_valid, chorus_valid, delay_valid;
  xadc_audio_in adc_input(.clk_xadc(clk_xadc),.rst_xadc(rst_xadc),
    .clk_100m(clk_100m),.rst(rst),.sample_tick_en(sample_tick_en),
    .vauxp4(vauxp4),.vauxn4(vauxn4),.audio_out(adc_audio),.out_valid(adc_valid));
  fx_overdrive_asym od(.clk(clk_100m),.rst(rst),.in_valid(adc_valid),
    .enable(frame_mode==1 || frame_mode==4),.audio_in(adc_audio),
    .drive(frame_drive),.tone_alpha(frame_alpha),.audio_out(od_audio),.out_valid(od_valid));
  fx_chorus_mod chorus(.clk(clk_100m),.rst(rst),.in_valid(od_valid),
    .enable(frame_mode==2 || frame_mode==4),.audio_in(od_audio),
    .depth(frame_depth),.audio_out(chorus_audio),.out_valid(chorus_valid));
  fx_delay_bram delay_fx(.clk(clk_100m),.rst(rst),.in_valid(chorus_valid),
    .enable(frame_mode==3 || frame_mode==4),.audio_in(chorus_audio),
    .delay_samples(frame_delay),.feedback(frame_feedback),
    .audio_out(delay_audio),.out_valid(delay_valid));
  always_ff @(posedge clk_100m)
    if(rst) audio_out<=0; else if(delay_valid) audio_out<=delay_audio;
  wire [15:0] audio_unsigned=audio_out ^ 16'h8000;
  sigma_delta_dac dac(.clk(clk_100m),.rst(rst),.audio_unsigned(audio_unsigned),.dac_out(dac_pwm_out));
endmodule

module pedal_debounce # (parameter integer STABLE_CYCLES=1_000_000)(
  input logic clk, rst, button,
  output logic level
);
  (* ASYNC_REG="TRUE" *) logic [1:0] sync_button;
  logic [$clog2(STABLE_CYCLES)-1:0] count;
  always_ff @(posedge clk) begin
    if(rst) begin sync_button<=0; count<=0; level<=0; end
    else begin
      sync_button<={sync_button[0],button};
      if(sync_button[1]==level) count<=0;
      else if(count==$clog2(STABLE_CYCLES)'(STABLE_CYCLES-1)) begin level<=sync_button[1]; count<=0; end
      else count<=count+1'b1;
    end
  end
endmodule
