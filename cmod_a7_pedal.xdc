# Digilent Cmod A7-35T, XC7A35T-1CPG236C. VAUX polarity corrected from request.
set_property -dict {PACKAGE_PIN L17 IOSTANDARD LVCMOS33} [get_ports sysclk]
create_clock -name sysclk -period 83.333333 [get_ports sysclk]
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS33} [get_ports {btn[0]}]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports {btn[1]}]
set_property -dict {PACKAGE_PIN A17 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN C16 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS33} [get_ports led0_r]
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports led0_g]
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33} [get_ports led0_b]
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS33} [get_ports uart_rx]
set_property -dict {PACKAGE_PIN M3 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports dac_pwm_out]
set_property -dict {PACKAGE_PIN G3 IOSTANDARD LVCMOS33} [get_ports vauxp4]
set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports vauxn4]
# Vivado derives both clocks through MMCMs/BUFGs. Do not blanket false-path
# the two domains: the bundled mailbox payload must retain a routing bound.
set_false_path -from [get_ports {btn[*] uart_rx}] -to [get_pins -hier -regexp {.*(sync_button_reg|rx_sync_reg)\[0\]/D}]
set_false_path -to [get_pins -hier -regexp {.*(ack_sync_reg|req_sync_reg)\[0\]/D}]
# Payload is held stable through a three-flop request synchronizer and ACK.
set_max_delay -datapath_only 15.0 -from [get_cells -hier -regexp {.*cdc_payload_reg\[[0-9]+\]}] -to [get_cells -hier -regexp {.*latest_reg\[[0-9]+\]}]
set_bus_skew 5.0 -from [get_cells -hier -regexp {.*cdc_payload_reg\[[0-9]+\]}] -to [get_cells -hier -regexp {.*latest_reg\[[0-9]+\]}]
# Asynchronous assertion of reset synchronizers; deassertion is synchronized.
set_false_path -to [get_pins -hier -filter {NAME =~ *por_pipe_reg*/CLR || NAME =~ *xr_pipe_reg*/PRE}]
# Board LEDs and analog bitstream have no receiving synchronous clock.
set_false_path -to [get_ports {led[*] led0_r led0_g led0_b dac_pwm_out}]
