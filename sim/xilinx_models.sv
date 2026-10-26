// Simulation-only functional models. Never include in Vivado synthesis.
`timescale 1ns/1ps
module IBUF(input wire I, output wire O); assign O=I; endmodule
module BUFG(input wire I, output wire O); assign O=I; endmodule
module MMCME2_BASE #(
  parameter real CLKIN1_PERIOD=83.333333, CLKFBOUT_MULT_F=50.0,
  parameter integer DIVCLK_DIVIDE=1,
  parameter real CLKOUT0_DIVIDE_F=6.0
)(input wire CLKIN1, CLKFBIN, RST, PWRDWN,
  output logic CLKOUT0=0, LOCKED=0,
  output wire CLKFBOUT, CLKFBOUTB, CLKOUT0B, CLKOUT1, CLKOUT1B,
  CLKOUT2,CLKOUT2B,CLKOUT3,CLKOUT3B,CLKOUT4,CLKOUT5,CLKOUT6);
  localparam real HALF=CLKIN1_PERIOD*DIVCLK_DIVIDE*CLKOUT0_DIVIDE_F/CLKFBOUT_MULT_F/2.0;
  always #(HALF) CLKOUT0=~CLKOUT0;
  initial begin #1000; LOCKED=1; end
  assign CLKFBOUT=CLKIN1;
  assign {CLKFBOUTB,CLKOUT0B,CLKOUT1,CLKOUT1B,CLKOUT2,CLKOUT2B,CLKOUT3,CLKOUT3B,CLKOUT4,CLKOUT5,CLKOUT6}=0;
endmodule
module XADC #(
  parameter logic [15:0] INIT_40=0, INIT_41=0, INIT_42=0
)(input wire DCLK,RESET,DEN,DWE,CONVST,CONVSTCLK,VP,VN,
  input wire [6:0] DADDR,
  input wire [15:0] DI,VAUXP,VAUXN,
  output logic [15:0] DO,
  output logic EOC, DRDY,
  output wire EOS,BUSY,OT,JTAGBUSY,JTAGLOCKED,JTAGMODIFIED,
  output wire [4:0] CHANNEL, MUXADDR,
  output wire [7:0] ALM);
  logic [11:0] sample_code=12'd2048;
  integer count=0;
  always @(posedge DCLK) begin
    if(RESET) begin count<=0; EOC<=0; DRDY<=0; DO<=0; end
    else begin
      EOC<=(count==103); count<=(count==103)?0:count+1;
      DRDY<=DEN;
      if(DEN) begin
        assert(DADDR==7'h14 && !DWE) else $fatal(1,"Bad DRP request");
        DO<={sample_code,4'b0};
      end
    end
  end
  assign {EOS,BUSY,OT,JTAGBUSY,JTAGLOCKED,JTAGMODIFIED,ALM}=0;
  assign CHANNEL=5'h14;
  assign MUXADDR=0;
endmodule
