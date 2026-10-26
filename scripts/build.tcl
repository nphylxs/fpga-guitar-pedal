set root [file normalize [file join [file dirname [info script]] ..]]
file mkdir $root/build
create_project -in_memory -part xc7a35tcpg236-1
read_verilog -sv $root/rtl/audio_math_pkg.sv
foreach f [glob $root/rtl/*.sv] {
  if {[file tail $f] ne "audio_math_pkg.sv"} {read_verilog -sv $f}
}
read_xdc $root/cmod_a7_pedal.xdc
synth_design -top cmod_a7_guitar_top -part xc7a35tcpg236-1
report_utilization -file $root/build/utilization_synth.rpt
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -report_unconstrained -file $root/build/timing.rpt
report_utilization -file $root/build/utilization.rpt
report_cdc -details -file $root/build/cdc.rpt
report_drc -file $root/build/drc.rpt
write_checkpoint -force $root/build/pedal_routed.dcp
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0} {
  error "Setup timing failed; inspect build/timing.rpt"
}
if {[get_property SLACK [get_timing_paths -delay_type min -max_paths 1]] < 0} {
  error "Hold timing failed; inspect build/timing.rpt"
}
write_bitstream -force $root/build/cmod_a7_pedal.bit
