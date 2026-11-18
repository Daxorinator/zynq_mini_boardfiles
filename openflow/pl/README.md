# PL designs (open flow)

Build: `./build.sh <project>` (Yosys + nextpnr-xilinx, output `build/<project>/<project>.bin`). Load on the board: `./load.sh build/<project>/<project>.bin <board-ip>`.
Every design instantiates `PS7` (required, see ../README.md) and uses the 50 MHz PL clock (K17).

| Project | What it shows | How it was checked |
|---|---|---|
| `blinky_ps7` | LED counter, keys light all LEDs | by eye |
| `oled` | SSD1306 OLED driven from the PL, KEY2 inverts | by eye |
| `axi_test`, `clkmeter` | PS-to-PL AXI (GP0): scratch register, I2C master to the EEPROM, PL clock frequency counters | `axi_run.py`, `run.py` on the board |
| `hdmi_640x480`, `hdmi_1280x720` | TMDS output with an OSERDES 10:1 + MMCM; the key-driven top selects bars / ramp / checkerboard / white | USB capture card, pixel-identical to a Vivado build |
| `hp_dma` | **PS and PL together**: the PL copies/checksums buffers in DDR through the PS's AXI high-performance port HP0, controlled over GP0, completion by status register and by interrupt (IRQ_F2P[0] via the stock UIO node) | `hp_dma_test.py`: copies from 128 B to 8 MiB identical, checksums match, interrupt wakes a sleeping process |
| `zm_base` | the open-flow counterpart of the Vivado `pltest` overlay: LEDs/keys, 34-pin header (inputs by default), I2C, OLED pins, PHY MDIO, timer interrupt, clock meters, HP-port DMA, all on one register map | `../py/tests/pltest_open.py` |
| `ple_mdio` | PL Ethernet PHY (RTL8211E) over MDIO bit-banged from the PS | PHY id read, link status |
| `ple_rgmii` | RGMII TX/RX through the PHY's digital loopback | `rgmii_run.py`: 60/60 bytes, repeated loads |
| `ple_mac` | **PL Ethernet over a real cable**: RGMII MAC front end in the PL (preamble/SFD/gap, raw frame capture), protocol in software on the PS (ARP, ICMP echo, UDP echo, FCS) | `ple_net.py selftest`: link 1000 Mb/s full duplex, ARP request answered by the peer with a valid FCS. `ple_net.py serve`: the laptop's ARP, `ping -n 6` and a UDP echo to 10.0.0.2 were all answered by the FPGA (board counters: arp_replies=1 icmp_replies=6 udp_echo=1). `test_protocol.py`: offline check of the protocol code |

Notes on the Ethernet parts:
- The RX path samples RGMII on the inverted RXC and TX uses a 125 MHz clock in phase with the data: this PHY adds its own TX delay and does not delay RXC. This is fixed at 1000 Mb/s (the TX clock does not change), so the PHY is told to advertise 1000BASE-T only (`mdio.py`).
- RGMII control: the first-edge sample of RX_CTL is DV, the second is DV xor error. Treating the second edge as DV makes PHY error flags look like frames.
- `ple_mac` has a small debug logic analyzer (arm with CTRL bit 3, samples at 0xA00) that was used to see the raw RGMII pins.
- Memory arrays written a byte at a time from one clock and read from another were mis-inferred by the tools: use whole-byte writes.
- Peers: the board is 10.0.0.2 (MAC 02:5a:59:4d:50:4c) and the laptop on the other end of the cable 10.0.0.1.
