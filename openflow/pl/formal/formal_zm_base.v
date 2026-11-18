module formal_zm_base(input clk50, input [1:0] key, output [3:0] led, inout [33:0] hdr, output eeprom_scl, inout eeprom_sda, output [3:0] oled,
                      output phy_rst_n, output phy_mdc, inout phy_mdio);
  zm_base dut(.clk50(clk50), .key(key), .led(led), .hdr(hdr), .eeprom_scl(eeprom_scl), .eeprom_sda(eeprom_sda), .oled(oled), .phy_rst_n(phy_rst_n), .phy_mdc(phy_mdc), .phy_mdio(phy_mdio));
endmodule
