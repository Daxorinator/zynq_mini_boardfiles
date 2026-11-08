# Builds the PS-only design for PYNQ on the ZYNQ MINI.
#
# Outputs (all under this pynq/ directory, and git-ignored):
#   ZynqMini/petalinux_bsp/hardware_project/ZynqMini.xsa  - hardware description for PetaLinux
#   ZynqMini/base/base.bit                                - empty-PL bitstream (BOOT.BIN needs one)
#   ZynqMini/base/base.hwh                                - hardware handoff for the "base" overlay
#
# usage: vivado -mode batch -source build_xsa.tcl -tclargs <path to this boardfiles repo>
set repo [file normalize [lindex $argv 0]]
set here [file normalize [file dirname [info script]]]
set hwdir  $here/ZynqMini/petalinux_bsp/hardware_project
set basedir $here/ZynqMini/base
set proj   $here/build/zm_ps

file mkdir $hwdir $basedir
set_param board.repoPaths [list $repo]
create_project -force zm_ps $proj -part xc7z010clg400-1
set_property board_part bochenjingxin:zynq_mini:part0:1.0 [current_project]

create_bd_design system
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset 1} $ps
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 0] $ps
validate_bd_design
save_bd_design

make_wrapper -files [get_files system.bd] -top
generate_target all [get_files system.bd]
add_files -norecurse [glob $proj/zm_ps.gen/sources_1/bd/system/hdl/system_wrapper.v]
set_property top system_wrapper [current_fileset]

write_hw_platform -fixed -force -file $hwdir/ZynqMini.xsa

# Bitstream: the design has no PL logic, but petalinux-package --boot --fpga needs a file.
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { error "implementation failed" }
file copy -force $proj/zm_ps.runs/impl_1/system_wrapper.bit $basedir/base.bit
file copy -force $proj/zm_ps.gen/sources_1/bd/system/hw_handoff/system.hwh $basedir/base.hwh
puts "XSA_DONE"
