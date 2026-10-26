module uart_param_ctrl #(
  parameter integer CLK_HZ=100_000_000,
  parameter integer BAUD=115200
)(
  input logic clk, rst, uart_rx,
  output logic [7:0] drive, tone, chorus_depth, delay_time, feedback
);
  localparam integer BIT_CLKS=(CLK_HZ+BAUD/2)/BAUD;
  (* ASYNC_REG="TRUE" *) logic [1:0] rx_sync;
  logic [1:0] rx_state, parse_state;
  logic [31:0] timer, packet_timer;
  logic [2:0] bit_index;
  logic [7:0] shift, byte_data, param_id;
  logic byte_valid, frame_error;
  always_ff @(posedge clk) begin
    if(rst) begin
      rx_sync<=2'b11; rx_state<=0; timer<=0; bit_index<=0;
      shift<=0; byte_data<=0; byte_valid<=0; frame_error<=0;
    end else begin
      rx_sync<={rx_sync[0],uart_rx}; byte_valid<=0; frame_error<=0;
      case(rx_state)
        0: if(!rx_sync[1]) begin timer<=BIT_CLKS/2-1; rx_state<=1; end
        1: if(timer!=0) timer<=timer-1;
           else if(!rx_sync[1]) begin timer<=BIT_CLKS-1; bit_index<=0; rx_state<=2; end
           else rx_state<=0;
        2: if(timer!=0) timer<=timer-1;
           else begin
             shift[bit_index]<=rx_sync[1]; timer<=BIT_CLKS-1;
             if(bit_index==7) rx_state<=3; else bit_index<=bit_index+1'b1;
           end
        3: if(timer!=0) timer<=timer-1;
           else begin
             if(rx_sync[1]) begin byte_data<=shift; byte_valid<=1; end
             else frame_error<=1;
             rx_state<=0;
           end
      endcase
    end
  end
  always_ff @(posedge clk) begin
    if(rst) begin
      drive<=48; tone<=96; chorus_depth<=100; delay_time<=142; feedback<=128;
      parse_state<=0; param_id<=0; packet_timer<=0;
    end else begin
      if(parse_state!=0) begin
        if(packet_timer==CLK_HZ/50-1) begin parse_state<=0; packet_timer<=0; end
        else packet_timer<=packet_timer+1;
      end
      if(frame_error) begin parse_state<=0; packet_timer<=0; end
      else if(byte_valid) begin
        packet_timer<=0;
        case(parse_state)
          0: if(byte_data==8'haa) parse_state<=1;
          1: if(byte_data>=1 && byte_data<=5) begin param_id<=byte_data; parse_state<=2; end
             else if(byte_data!=8'haa) parse_state<=0;
          2: begin
            case(param_id)
              1: drive<=byte_data;
              2: tone<=byte_data;
              3: chorus_depth<=byte_data;
              4: delay_time<=byte_data;
              5: feedback<=(byte_data>240)?8'd240:byte_data;
              default: ;
            endcase
            parse_state<=0;
          end
          default: parse_state<=0;
        endcase
      end
    end
  end
endmodule
