# PL test overlay for the ZYNQ MINI: one design that exercises the PL side without any cable or add-on board.
#
#   leds, keys     AXI GPIO on the board LEDs / KEY2, KEY3
#   hdr0, hdr1     AXI GPIO, 32 + 2 bidirectional bits on the 34 expansion header signals
#   clk_wiz        MMCM from the 50 MHz PL oscillator: 50 / 100 / 150 / 200 MHz
#   fm             frequency meter (RTL) for the four MMCM outputs and PS FCLK1, FCLK2 against FCLK0
#   fm0..fm2       AXI GPIO inputs carrying the six counts, status = MMCM locked
#   timer          AXI Timer, interrupt IRQ_F2P[0]
#   dma            AXI DMA (simple mode), MM2S looped back to S2MM, interrupts IRQ_F2P[1], [2]
#   eeprom         AXI GPIO bit-banging the AT24C02 I2C bus (open drain via tri-state)
#   oled           AXI GPIO bit-banging the SSD1306 SPI interface
#   ple            AXI GPIO bit-banging RGMII_RESET / MDC / MDIO of the PL Ethernet PHY
#
# Outputs (git-ignored): overlay/out/pltest.bit, pltest.hwh, pltest.dtbo
# usage: vivado -mode batch -source build_pltest.tcl -tclargs <boardfiles repo> [jobs]
set repo [file normalize [lindex $argv 0]]
set jobs [expr {[llength $argv] > 1 ? [lindex $argv 1] : 4}]
set here [file normalize [file dirname [info script]]]
set proj $here/../../build/pltest
set_param board.repoPaths [list $repo]
create_project -force pltest $proj -part xc7z010clg400-1
set_property board_part bochenjingxin:zynq_mini:part0:1.0 [current_project]
add_files -norecurse $here/freq_meter.v
add_files -fileset constrs_1 -norecurse $here/pltest.xdc
create_bd_design system

# ---- PS ------------------------------------------------------------------------------------------
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset 1} $ps
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 100 \
    CONFIG.PCW_EN_CLK1_PORT 1 CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ 50 \
    CONFIG.PCW_EN_CLK2_PORT 1 CONFIG.PCW_FPGA2_PERIPHERAL_FREQMHZ 75 \
    CONFIG.PCW_USE_S_AXI_HP0 1 \
    CONFIG.PCW_USE_FABRIC_INTERRUPT 1 CONFIG.PCW_IRQ_F2P_INTR 1] $ps

# ---- board LEDs / keys -----------------------------------------------------------------------------
set leds [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio leds]
set_property -dict [list CONFIG.GPIO_BOARD_INTERFACE leds_4bits CONFIG.C_ALL_OUTPUTS 1] $leds
set keys [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio keys]
set_property -dict [list CONFIG.GPIO_BOARD_INTERFACE push_buttons_2bits CONFIG.C_ALL_INPUTS 1 CONFIG.C_INTERRUPT_PRESENT 1] $keys
apply_board_connection -board_interface leds_4bits -ip_intf leds/GPIO -diagram system
apply_board_connection -board_interface push_buttons_2bits -ip_intf keys/GPIO -diagram system

# ---- header, EEPROM, OLED, PL Ethernet management ----------------------------------------------------
proc bidir_gpio {name width} {
    set g [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio $name]
    set_property -dict [list CONFIG.C_GPIO_WIDTH $width CONFIG.C_ALL_INPUTS 0 CONFIG.C_ALL_OUTPUTS 0 \
        CONFIG.C_TRI_DEFAULT [format 0x%X [expr {(1 << $width) - 1}]] CONFIG.C_DOUT_DEFAULT 0x0] $g
    make_bd_intf_pins_external -name $name [get_bd_intf_pins $name/GPIO]
    return $g
}
bidir_gpio hdr0 32
bidir_gpio hdr1 2
bidir_gpio eeprom 2
bidir_gpio ple 3
set oled [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio oled]
set_property -dict [list CONFIG.C_GPIO_WIDTH 4 CONFIG.C_ALL_OUTPUTS 1] $oled
make_bd_intf_pins_external -name oled [get_bd_intf_pins oled/GPIO]

# ---- clocks and frequency meter -------------------------------------------------------------------
create_bd_port -dir I -type clk -freq_hz 50000000 pl_clk_50m
set cw [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_wiz]
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ 50.000 CONFIG.PRIMITIVE MMCM CONFIG.USE_RESET false CONFIG.USE_LOCKED true \
    CONFIG.NUM_OUT_CLKS 4 \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 50  CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 100 \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ 150 CONFIG.CLKOUT4_REQUESTED_OUT_FREQ 200 \
    CONFIG.CLKOUT2_USED true CONFIG.CLKOUT3_USED true CONFIG.CLKOUT4_USED true] $cw
connect_bd_net [get_bd_ports pl_clk_50m] [get_bd_pins clk_wiz/clk_in1]

set fm [create_bd_cell -type module -reference freq_meter fm]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins fm/ref_clk]
connect_bd_net [get_bd_pins clk_wiz/clk_out1] [get_bd_pins fm/clk0]
connect_bd_net [get_bd_pins clk_wiz/clk_out2] [get_bd_pins fm/clk1]
connect_bd_net [get_bd_pins clk_wiz/clk_out3] [get_bd_pins fm/clk2]
connect_bd_net [get_bd_pins clk_wiz/clk_out4] [get_bd_pins fm/clk3]
connect_bd_net [get_bd_pins ps7/FCLK_CLK1]    [get_bd_pins fm/clk4]
connect_bd_net [get_bd_pins ps7/FCLK_CLK2]    [get_bd_pins fm/clk5]
for {set k 0} {$k < 3} {incr k} {
    set g [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio fm$k]
    set_property -dict [list CONFIG.C_GPIO_WIDTH 32 CONFIG.C_ALL_INPUTS 1 CONFIG.C_IS_DUAL 1 \
        CONFIG.C_GPIO2_WIDTH 32 CONFIG.C_ALL_INPUTS_2 1] $g
    connect_bd_net [get_bd_pins fm/count[expr {2*$k}]]   [get_bd_pins fm$k/gpio_io_i]
    connect_bd_net [get_bd_pins fm/count[expr {2*$k+1}]] [get_bd_pins fm$k/gpio2_io_i]
}
set st [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio status]
set_property -dict [list CONFIG.C_GPIO_WIDTH 1 CONFIG.C_ALL_INPUTS 1 CONFIG.C_IS_DUAL 1 \
    CONFIG.C_GPIO2_WIDTH 32 CONFIG.C_ALL_INPUTS_2 1] $st
set lk [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat lockcat]
set_property -dict [list CONFIG.NUM_PORTS 1 CONFIG.IN0_WIDTH 1] $lk
connect_bd_net [get_bd_pins clk_wiz/locked] [get_bd_pins lockcat/In0]
connect_bd_net [get_bd_pins lockcat/dout] [get_bd_pins status/gpio_io_i]
connect_bd_net [get_bd_pins fm/gate_id] [get_bd_pins status/gpio2_io_i]

# ---- timer, DMA, interrupts ---------------------------------------------------------------------------
set tm [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_timer timer]
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma dma]
set_property -dict [list CONFIG.c_include_sg 0 CONFIG.c_sg_include_stscntrl_strm 0 \
    CONFIG.c_m_axi_mm2s_data_width 32 CONFIG.c_m_axis_mm2s_tdata_width 32 \
    CONFIG.c_include_mm2s_dre 1 CONFIG.c_include_s2mm_dre 1 CONFIG.c_sg_length_width 23] $dma
connect_bd_intf_net [get_bd_intf_pins dma/M_AXIS_MM2S] [get_bd_intf_pins dma/S_AXIS_S2MM]
set irq [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat irqcat]
set_property CONFIG.NUM_PORTS 4 $irq
connect_bd_net [get_bd_pins timer/interrupt]       [get_bd_pins irqcat/In0]
connect_bd_net [get_bd_pins dma/mm2s_introut]      [get_bd_pins irqcat/In1]
connect_bd_net [get_bd_pins dma/s2mm_introut]      [get_bd_pins irqcat/In2]
connect_bd_net [get_bd_pins keys/ip2intc_irpt]     [get_bd_pins irqcat/In3]
connect_bd_net [get_bd_pins irqcat/dout] [get_bd_pins ps7/IRQ_F2P]

# ---- AXI plumbing -------------------------------------------------------------------------------------------
foreach ip {leds keys hdr0 hdr1 eeprom oled ple fm0 fm1 fm2 status timer dma} {
    set pin [expr {$ip eq "dma" ? "dma/S_AXI_LITE" : "$ip/S_AXI"}]
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
        -config {Master "/ps7/M_AXI_GP0" Clk "Auto"} [get_bd_intf_pins $pin]
}
# Both DMA data masters share ONE interconnect to HP0 (separate automation calls would give S2MM its own,
# unconnected interconnect and the loopback would stall).
set mic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect mem_ic]
set_property -dict [list CONFIG.NUM_SI 2 CONFIG.NUM_MI 1] $mic
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_MM2S] [get_bd_intf_pins mem_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_S2MM] [get_bd_intf_pins mem_ic/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins mem_ic/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins mem_ic/ACLK] [get_bd_pins mem_ic/S00_ACLK] \
    [get_bd_pins mem_ic/S01_ACLK] [get_bd_pins mem_ic/M00_ACLK] [get_bd_pins ps7/S_AXI_HP0_ACLK] \
    [get_bd_pins dma/m_axi_mm2s_aclk] [get_bd_pins dma/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins mem_ic/ARESETN] \
    [get_bd_pins mem_ic/S00_ARESETN] [get_bd_pins mem_ic/S01_ARESETN] [get_bd_pins mem_ic/M00_ARESETN]

assign_bd_address -offset 0x42800000 -range 64K [get_bd_addr_segs timer/S_AXI/Reg]
assign_bd_address -offset 0x40400000 -range 64K [get_bd_addr_segs dma/S_AXI_LITE/Reg]
assign_bd_address
validate_bd_design
save_bd_design
make_wrapper -files [get_files system.bd] -top
generate_target all [get_files system.bd]
add_files -norecurse [glob $proj/pltest.gen/sources_1/bd/system/hdl/system_wrapper.v]
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { error "implementation failed" }

file mkdir $here/../out
file copy -force $proj/pltest.runs/impl_1/system_wrapper.bit $here/../out/pltest.bit
file copy -force $proj/pltest.gen/sources_1/bd/system/hw_handoff/system.hwh $here/../out/pltest.hwh
exec dtc -@ -W no-interrupts_property -I dts -O dtb -o $here/../out/pltest.dtbo $here/pltest.dtso
puts "PLTEST_DONE"
