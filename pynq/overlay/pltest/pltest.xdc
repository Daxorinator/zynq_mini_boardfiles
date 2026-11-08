# ZYNQ MINI PL test overlay constraints (XC7Z010-1CLG400). Pin sources: docs/ZYNQ_MINI_Hardware_Specification_EN.md
# sections 8, 10, 11, 12. LEDs and KEY2/KEY3 come from the board part, not from this file.

# 50 MHz PL oscillator
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports pl_clk_50m]
create_clock -period 20.000 -name pl_clk_50m [get_ports pl_clk_50m]

# 40-pin expansion header, 34 signals, weak pull-downs so a floating pin reads 0 (a pin that follows a driven
# neighbour is then a real short, not coupling). Explicit lines: loops are not allowed in XDC. Bit order = hdr0[0..31]
# then hdr1[0..1]:
# right column header pins 2..18 (top to bottom), then left column pins 39..23.
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[0]}]
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[1]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[2]}]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[3]}]
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[4]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[5]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[6]}]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[7]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[8]}]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[9]}]
set_property -dict {PACKAGE_PIN T17 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[10]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[11]}]
set_property -dict {PACKAGE_PIN W20 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[12]}]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[13]}]
set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[14]}]
set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[15]}]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[16]}]
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[17]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[18]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[19]}]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[20]}]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[21]}]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[22]}]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[23]}]
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[24]}]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[25]}]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[26]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[27]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[28]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[29]}]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[30]}]
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr0_tri_io[31]}]
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr1_tri_io[0]}]
set_property -dict {PACKAGE_PIN N20 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW PULLDOWN true} [get_ports {hdr1_tri_io[1]}]

# AT24C02 EEPROM on the PL I2C bus (bit-banged through AXI GPIO, open drain by tri-stating)
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33} [get_ports {eeprom_tri_io[0]}]   ;# SCL
set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33} [get_ports {eeprom_tri_io[1]}]   ;# SDA

# 0.96" SSD1306 OLED, SPI: D0 = SCLK, D1 = MOSI, then DC and RES (outputs only)
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports {oled_tri_o[0]}]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports {oled_tri_o[1]}]
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33} [get_ports {oled_tri_o[2]}]
set_property -dict {PACKAGE_PIN F17 IOSTANDARD LVCMOS33} [get_ports {oled_tri_o[3]}]

# PL Ethernet PHY (RTL8211E-VB) management: RGMII_RESET, MDC, MDIO
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports {ple_tri_io[0]}]
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports {ple_tri_io[1]}]
set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS33} [get_ports {ple_tri_io[2]}]

# Clock-domain crossings in the frequency meter are Gray-coded two-flop synchronisers
set_false_path -to [get_cells -hier -filter {NAME =~ *sync0_reg*}]
