`timescale 1ns/1ps
module tb_input;
  logic clk=0, adc_clk=0, rst=1;
  always #5 clk=~clk;
  always #4.807692 adc_clk=~adc_clk;
  logic [10:0] counter=0;
  wire tick=counter==2047;
  always @(posedge clk) if(rst) counter<=0; else counter<=counter+1'b1;
  wire signed [15:0] audio;
  wire valid;
  xadc_audio_in dut(adc_clk,rst,clk,rst,tick,1'b0,1'b0,audio,valid);
  integer cycles=0, last_valid=0, frames=0;
  /* verilator lint_off BLKSEQ */
  always @(negedge clk) begin
    cycles++;
    if(!rst && valid) begin
      if(last_valid!=0) assert(cycles-last_valid==2048) else $fatal(1,"Sample spacing");
      last_valid=cycles; frames++;
    end
  end
  initial begin
    repeat(10) @(negedge clk); rst=0;
    wait(frames==5); @(negedge clk);
    assert(audio==0) else $fatal(1,"Midpoint");
    dut.adc.sample_code=3072;
    wait(frames==7); @(negedge clk);
    assert(audio>15000 && audio<16500) else $fatal(1,"Input scale/polarity %0d",audio);
    assert(dut.latest==49152) else $fatal(1,"Boxcar/CDC %0d",dut.latest);
    wait(frames==1500); @(negedge clk);
    assert(audio>=-2 && audio<=12) else $fatal(1,"DC decay %0d",audio);
    dut.adc.sample_code=0;
    wait(frames==1502); @(negedge clk);
    assert(audio==-32768) else $fatal(1,"HP saturation %0d",audio);
    $display("PASS: XADC DRP, boxcar, CDC, exact sample spacing, scaling, DC rejection, saturation");
    $finish;
  end
  initial begin #100_000_000; $fatal(1,"Timeout"); end
endmodule
