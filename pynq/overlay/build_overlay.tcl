# LED + key overlay: two AXI GPIO blocks on the board's leds_4bits and push_buttons_2bits.
#   leds  @ 0x41200000  (4 outputs, active high, LED1..LED4 = T12 U12 V12 W13)
#   keys  @ 0x41210000  (2 inputs, active low, KEY2/KEY3 = M20 M19)
#
# Outputs (git-ignored): overlay/out/leds_keys.bit and leds_keys.hwh
# usage: vivado -mode batch -source build_overlay.tcl -tclargs <path to this boardfiles repo>
set repo [file normalize [lindex $argv 0]]
set here [file normalize [file dirname [info script]]]
set proj $here/../build/ov
set_param board.repoPaths [list $repo]
create_project -force ov $proj -part xc7z010clg400-1
set_property board_part bochenjingxin:zynq_mini:part0:1.0 [current_project]
create_bd_design system

set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset 1} $ps

set leds [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio leds]
set_property -dict [list CONFIG.GPIO_BOARD_INTERFACE leds_4bits CONFIG.C_ALL_OUTPUTS 1] $leds
set keys [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio keys]
set_property -dict [list CONFIG.GPIO_BOARD_INTERFACE push_buttons_2bits CONFIG.C_ALL_INPUTS 1] $keys
apply_board_connection -board_interface leds_4bits -ip_intf leds/GPIO -diagram system
apply_board_connection -board_interface push_buttons_2bits -ip_intf keys/GPIO -diagram system

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps7/M_AXI_GP0" Clk "Auto"} [get_bd_intf_pins leds/S_AXI]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps7/M_AXI_GP0" Clk "Auto"} [get_bd_intf_pins keys/S_AXI]

assign_bd_address
validate_bd_design
save_bd_design
make_wrapper -files [get_files system.bd] -top
generate_target all [get_files system.bd]
add_files -norecurse [glob $proj/ov.gen/sources_1/bd/system/hdl/system_wrapper.v]
set_property top system_wrapper [current_fileset]

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { error "implementation failed" }

file mkdir $here/out
file copy -force $proj/ov.runs/impl_1/system_wrapper.bit $here/out/leds_keys.bit
file copy -force $proj/ov.gen/sources_1/bd/system/hw_handoff/system.hwh $here/out/leds_keys.hwh
puts "OVERLAY_DONE"
