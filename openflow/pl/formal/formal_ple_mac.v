module formal_ple_mac(input clk50, input [1:0] key, output [3:0] led, output phy_rst_n, output phy_mdc, inout phy_mdio,
                      output rgmii_txc, output rgmii_tx_ctl, output [3:0] rgmii_txd, input rgmii_rxc, input rgmii_rx_ctl, input [3:0] rgmii_rxd);
  ple_mac dut(.*);
endmodule
