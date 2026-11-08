# HDMI test pattern overlay (RTL TMDS transmitter, no licensed IP). BUILD-ONLY: it has not been run with a monitor.
#   ctrl  AXI GPIO @ auto address, 3 outputs: bit0 = HDMI 5 V output enable, bits 2:1 = pattern (0 bars, 1 ramp, 2 checks, 3 white)
# Outputs (git-ignored): overlay/out/hdmi_test.bit / .hwh
# usage: vivado -mode batch -source build_hdmi_test.tcl -tclargs <boardfiles repo> [jobs]
set repo [file normalize [lindex $argv 0]]
set jobs [expr {[llength $argv] > 1 ? [lindex $argv 1] : 4}]
set here [file normalize [file dirname [info script]]]
set proj $here/../../build/hdmi_test
set_param board.repoPaths [list $repo]
create_project -force hdmi_test $proj -part xc7z010clg400-1
set_property board_part bochenjingxin:zynq_mini:part0:1.0 [current_project]
add_files -norecurse $here/hdmi_tx.v
add_files -fileset constrs_1 -norecurse $here/hdmi.xdc
create_bd_design system

set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset 1} $ps

set ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio ctrl]
set_property -dict [list CONFIG.C_GPIO_WIDTH 3 CONFIG.C_ALL_OUTPUTS 1] $ctrl
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps7/M_AXI_GP0" Clk "Auto"} [get_bd_intf_pins ctrl/S_AXI]

set en  [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice en]
set_property -dict [list CONFIG.DIN_WIDTH 3 CONFIG.DIN_FROM 0 CONFIG.DIN_TO 0 CONFIG.DOUT_WIDTH 1] $en
set pat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice pat]
set_property -dict [list CONFIG.DIN_WIDTH 3 CONFIG.DIN_FROM 2 CONFIG.DIN_TO 1 CONFIG.DOUT_WIDTH 2] $pat
connect_bd_net [get_bd_pins ctrl/gpio_io_o] [get_bd_pins en/Din]
connect_bd_net [get_bd_pins ctrl/gpio_io_o] [get_bd_pins pat/Din]

set hd [create_bd_cell -type module -reference hdmi_tx hdmi]
connect_bd_net [get_bd_pins en/Dout]  [get_bd_pins hdmi/enable]
connect_bd_net [get_bd_pins pat/Dout] [get_bd_pins hdmi/pattern]
foreach p {clk50 tmds_clk_p tmds_clk_n tmds_d_p tmds_d_n hdmi_oe} {
    make_bd_pins_external -name $p [get_bd_pins hdmi/$p]
}

assign_bd_address
validate_bd_design
save_bd_design
make_wrapper -files [get_files system.bd] -top
generate_target all [get_files system.bd]
add_files -norecurse [glob $proj/hdmi_test.gen/sources_1/bd/system/hdl/system_wrapper.v]
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { error "implementation failed" }
file mkdir $here/../out
file copy -force $proj/hdmi_test.runs/impl_1/system_wrapper.bit $here/../out/hdmi_test.bit
file copy -force $proj/hdmi_test.gen/sources_1/bd/system/hw_handoff/system.hwh $here/../out/hdmi_test.hwh
puts "HDMI_DONE"
