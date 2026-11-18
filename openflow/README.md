# Open-source flow for the ZYNQ MINI

Everything here runs on open-source tools: the FPGA fabric (PL), the boot chain from the first stage up (PS7 init, U-Boot SPL),
and the tests. The Vivado board files in `../zynq_mini/` and the PYNQ image in `../pynq/` are unchanged and independent of this folder.

| Folder | What |
|---|---|
| `pl/` | PL designs built with Yosys + nextpnr-xilinx (openXC7): LED/key blinky, OLED, I2C EEPROM + PS-PL AXI test, clock meter, HDMI 640x480 and 1280x720, a PL DMA through the HP port with interrupt, PL Ethernet (MDIO, RGMII loopback, MAC front end). `./build.sh <project>`, `./load.sh <file.bin>` |
| `boot/` | PS bring-up without Vivado: hand-written `ps7_init` (`boot/ps7`), U-Boot SPL build (`boot/build.sh` -> `BOOT.BIN`, `u-boot.img`), bare-metal DDR test, an open BOOT.BIN assembler |
| `tests/` | Board tests: DDR stability (bare-metal and Linux), HDMI capture-card check |

Status (tested on REV B, XC7Z010-1CLG400, 2026-11):
- PL: LEDs, keys, OLED, I2C EEPROM, PS-to-PL AXI, HDMI at 640x480 and 1280x720 (checked with a USB capture card).
- PS and PL together: a PL DMA block moving data to and from DDR through the PS's AXI high-performance port, controlled from Linux, with an interrupt that wakes a sleeping process (`pl/hp_dma`).
- PL Ethernet over a real cable at 1000 Mb/s: MAC front end in the PL, protocol stack in software on the PS (`pl/ple_mac`); an ARP request sent by the FPGA is answered by the peer.
- Memory: the boot chain's DDR init passes a bare-metal 511 MiB random-pattern test and a two-core Linux memory stress (`tests/`).
- Boot: boot ROM -> open-built U-Boot SPL (hand-written PS7 init) -> U-Boot -> PYNQ Linux, from the SD card.
- Not independent of Xilinx tools: the DDR PHY tuning values in the PS7 init, and the U-Boot device tree (`pcw.dtsi`), both derived from the Vivado hardware export.

## Toolchain (not in the repo)
- PL: openXC7 (nextpnr-xilinx + Project X-Ray database, tested 2026-10-18) and oss-cad-suite (Yosys, openFPGALoader, 2026-10-14), unpacked under `~/openxc7/{tc,oss-cad-suite}` (or set `OPENXC7_HOME`). See `pl/env.sh`.
- Boot: any bare-metal `arm-none-eabi-gcc`, bison, flex, curl. The U-Boot source is fetched by `boot/build.sh` (Xilinx tag `xilinx-v2024.1`, SHA-256 pinned).

## Rules learned the hard way
- **Every PL design must instantiate `PS7`** (`(* keep *) PS7 ps7 ();`). A bitstream without it froze the PS twice when loaded through the Linux FPGA manager.
- **Avoid DSP48 inference** in nextpnr-xilinx designs: a Yosys-inferred DSP (a constant multiplier) corrupted the HDMI output. Use shift-and-add.
- The USB HDMI capture card's no-signal screen is also colour bars; compare against that reference before believing a picture (`tests/hdmi_capture`).
- U-Boot's one-shot `uEnv.txt` mechanism (used by the tests) drops lines over ~300 characters silently: split commands into several variables.

## Licences
Own code (`pl/`, `boot/ps7/*.c|h`, `tests/`) is MIT like the rest of the repo. `boot/uboot/overlay` and `boot/ps7/vivado_ref` are derived from U-Boot and from Xilinx's generated `ps7_init_gpl.c` and are GPL-2.0-or-later, see their headers.
