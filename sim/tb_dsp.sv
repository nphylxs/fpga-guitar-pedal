`timescale 1ns/1ps
module tb_dsp;
  logic clk=0, rst=1;
  always #5 clk=~clk;
  logic valid=0, en=1;
  logic signed [15:0] din=0, dout, cout, oout;
  logic dv,cv,ov;
  logic [15:0] ds=3;
  logic [7:0] fb=0, depth=0, drive=0;
  fx_delay_bram delay_dut(clk,rst,valid,en,din,ds,fb,dout,dv);
  fx_chorus_mod #(.LFO_STEP(32'd1431655)) chorus_dut(clk,rst,valid,en,din,depth,cout,cv);
  fx_overdrive_asym od_dut(clk,rst,valid,en,din,drive,16'd65535,oout,ov);
  logic [15:0] dac_input=32768;
  wire bit_out;
  sigma_delta_dac dac(clk,rst,dac_input,bit_out);
  logic rx=1;
  wire [7:0] drive_r,tone_r,depth_r,time_r,fb_r;
  uart_param_ctrl uart(clk,rst,rx,drive_r,tone_r,depth_r,time_r,fb_r);
  task automatic reset_all;
    @(negedge clk); rst=1; repeat(4) @(negedge clk); rst=0;
  endtask
  task automatic frame(input integer x);
    @(negedge clk); din=16'(x); valid=1;
    @(negedge clk); valid=0;
    repeat(10) @(negedge clk);
  endtask
  task automatic send_byte(input logic [7:0] b, input logic stop_good=1);
    @(negedge clk); rx=0; repeat(868) @(negedge clk);
    for(int j=0;j<8;j++) begin rx=b[j]; repeat(868) @(negedge clk); end
    rx=stop_good; repeat(868) @(negedge clk);
    rx=1; repeat(868) @(negedge clk);
  endtask
  integer ones,expected;
  integer previous, pos, neg;
  integer reference_samples[0:2999];
  integer phase_index, sine_value, delay_q8_ref, lag, frac, near_ref, far_ref, wet_ref, input_ref;
  real sine_real;
  initial begin
    reset_all();
    for(int n=0;n<8;n++) begin
      frame(n==0?16000:0);
      assert(dout==(n==0?16000:(n==3?8000:0))) else $fatal(1,"Delay impulse n=%0d out=%0d",n,dout);
    end
    reset_all(); ds=32768;
    for(int n=0;n<=32770;n++) begin
      frame(n==0?16000:0);
      assert(dout==(n==0?16000:(n==32768?8000:0))) else $fatal(1,"Delay max/wrap n=%0d out=%0d",n,dout);
      if(n<=770) assert(cout==((n==0 || n==768)?8000:0)) else $fatal(1,"Chorus impulse n=%0d out=%0d",n,cout);
    end
    reset_all(); depth=255;
    for(int n=0;n<3000;n++) begin
      // Accelerate phase coverage in this scoreboard: cover an entire LFO
      // cycle, including negative modulation and negative tap differences.
      phase_index=int'(chorus_dut.phase[31:24]);
      sine_real=32767.0*$sin(6.283185307179586*real'(phase_index)/256.0);
      sine_value=$rtoi(sine_real+(sine_real>=0?0.5:-0.5));
      delay_q8_ref=196608+((sine_value*510) >>> 7);
      lag=delay_q8_ref >>> 8; frac=delay_q8_ref & 255;
      near_ref=(n>=lag)?reference_samples[n-lag]:0;
      far_ref=(n>lag)?reference_samples[n-lag-1]:0;
      wet_ref=near_ref+(((far_ref-near_ref)*frac) >>> 8);
      input_ref=((n*997)%60000)-30000;
      reference_samples[n]=input_ref;
      frame(input_ref);
      assert(int'(cout)==((input_ref+wet_ref) >>> 1)) else
        $fatal(1,"Fractional chorus n=%0d got=%0d expected=%0d",n,cout,((input_ref+wet_ref) >>> 1));
    end
    // Reset must hide stale BRAM contents without clearing the arrays.
    reset_all(); ds=1;
    for(int n=0;n<20;n++) begin frame(0); assert(dout==0 && cout==0); end
    en=0;
    for(int n=-32768;n<32768;n+=997) begin
      frame(n); assert(dout==din && cout==din && oout==din) else $fatal(1,"Bypass");
    end
    en=1; drive=255; frame(-32768); frame(-32768); previous=-32768;
    for(int n=-32768;n<32768;n+=257) begin
      frame(n);
      assert(int'(oout)>=previous) else $fatal(1,"Clipper not monotonic"); previous=int'(oout);
    end
    frame(32767); pos=int'(oout); frame(-32768); neg=int'(oout);
    assert(pos>24000 && neg > -17000 && neg < -16000) else $fatal(1,"Clip asymmetry pos=%0d neg=%0d",pos,neg);
    ds=1; fb=240;
    for(int n=0;n<2000;n++) begin frame(32767); assert(dout>=0) else $fatal(1,"Feedback overflow"); end
    for(int n=0;n<2000;n++) begin frame(-32768); assert(dout<=0) else $fatal(1,"Negative feedback overflow"); end
    for(int code=0;code<=4;code++) begin
      dac_input=(code==4)?16'hffff:16'(code*16384);
      repeat(1000) @(negedge clk);
      ones=0;
      repeat(65536) begin
        @(negedge clk); ones+=int'(bit_out);
        assert(dac.i1<500000 && dac.i1 > -500000 && dac.i2<500000 && dac.i2 > -500000)
          else $fatal(1,"DAC unstable");
      end
      expected=16384+int'(dac_input)/2;
      assert(ones>=expected-4 && ones<=expected+4) else $fatal(1,"DAC density %0d != %0d",ones,expected);
    end
    for(int n=0;n<1000;n++) begin
      dac_input=16'($urandom);
      repeat(2048) begin
        @(negedge clk);
        assert(dac.i1<500000 && dac.i1 > -500000 && dac.i2<500000 && dac.i2 > -500000)
          else $fatal(1,"DAC transition instability");
      end
    end
    send_byte(8'haa); send_byte(1); send_byte(8'hff);
    assert(drive_r==255) else $fatal(1,"UART drive");
    send_byte(8'haa); send_byte(5); send_byte(255);
    assert(fb_r==240) else $fatal(1,"UART feedback clamp");
    send_byte(8'haa); send_byte(2); send_byte(8'haa);
    assert(tone_r==170) else $fatal(1,"UART AA payload");
    send_byte(8'haa); send_byte(3); send_byte(99,0);
    assert(depth_r==100) else $fatal(1,"UART framing");
    send_byte(8'haa); send_byte(4); send_byte(0);
    assert(time_r==0) else $fatal(1,"UART recovery");
    $display("PASS: DSP impulses, max delay/wrap, reset, bypass, clipping, feedback, DAC density/stability, UART");
    $finish;
  end
  initial begin #100_000_000; $fatal(1,"Timeout"); end
endmodule
