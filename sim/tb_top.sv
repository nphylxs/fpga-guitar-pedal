`timescale 1ns/1ps
module tb_top;
  logic sysclk=0;
  always #41.666667 sysclk=~sysclk;
  logic [1:0] btn=0;
  wire dac;
  wire [1:0] leds;
  wire r,g,b;
  cmod_a7_guitar_top dut(sysclk,btn,1'b0,1'b0,1'b1,dac,leds,r,g,b);
  integer cycles=0,last_tick=0,last_output=0;
  /* verilator lint_off BLKSEQ */
  always @(negedge dut.clk_100m) begin
    cycles++;
    if(dut.rst) begin last_tick=0; last_output=0; end
    else begin
      if(dut.sample_tick_en) begin
        if(last_tick!=0) assert(cycles-last_tick==2048) else $fatal(1,"Top sample tick");
        last_tick=cycles;
      end
      if(dut.delay_valid) begin
        if(last_output!=0) assert(cycles-last_output==2048) else $fatal(1,"Top output cadence");
        assert(cycles-last_tick<32) else $fatal(1,"Pipeline deadline");
        last_output=cycles;
      end
    end
  end
  initial begin
    wait(!dut.rst); repeat(4096) @(negedge dut.clk_100m);
    assert(dut.mode==0 && leds==0 && {r,g,b}==0);
    btn[1]=1; repeat(100) @(negedge dut.clk_100m); btn[1]=0;
    repeat(100) @(negedge dut.clk_100m);
    assert(dut.mode==0) else $fatal(1,"Button bounce accepted");
    for(int mode_num=1;mode_num<=5;mode_num++) begin
      btn[1]=1; repeat(1_000_010) @(negedge dut.clk_100m);
      assert(int'(dut.mode)==mode_num%5) else $fatal(1,"Mode advance");
      repeat(4096) @(negedge dut.clk_100m);
      assert(int'(dut.mode)==mode_num%5) else $fatal(1,"Held button repeats");
      btn[1]=0; repeat(1_000_010) @(negedge dut.clk_100m);
    end
    btn[0]=1; repeat(1_000_010) @(negedge dut.clk_100m);
    assert(dut.rst && dut.mode==0) else $fatal(1,"Debounced reset");
    btn[0]=0; repeat(1_000_010) @(negedge dut.clk_100m);
    repeat(4096) @(negedge dut.clk_100m);
    assert(!dut.rst && !dut.rst_xadc && dut.audio_out==0) else $fatal(1,"Reset recovery");
    $display("PASS: integrated pipeline cadence/deadline, button bounce/hold, five modes, reset recovery");
    $finish;
  end
  initial begin #200_000_000; $fatal(1,"Timeout"); end
endmodule
