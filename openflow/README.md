# Open-source flow for the ZYNQ MINI

Everything here runs on open-source tools: the FPGA fabric (PL), the boot chain from the first stage up (PS7 init, U-Boot SPL),
and the tests. The Vivado board files in `../zynq_mini/` and the PYNQ image in `../pynq/` are unchanged and independent of this folder.

| Folder | What |
|---|---|
| `pl/` | PL designs built with Yosys + nextpnr-xilinx (openXC7): LED/key blinky, OLED, I2C EEPROM + PS-PL AXI test, clock meter, HDMI 640x480 and 1280x720, a PL DMA through the HP port with interrupt, PL Ethernet (MDIO, RGMII loopback, MAC front end). `./build.sh <project>`, `./load.sh <file.bin>` |
| `boot/` | PS bring-up without Vivado: hand-written `ps7_init` (`boot/ps7`), U-Boot SPL build (`boot/build.sh` -> `BOOT.BIN`, `u-boot.img`), bare-metal DDR test, an open BOOT.BIN assembler |
| `buildroot/` | Open-source userland: cross toolchain and root filesystem built from source (Buildroot); `build_all.sh` in this folder builds the whole open path into one SD image |
| `linux/` | Open Linux: kernel build, hand-written device tree, `zmbuf` DMA-buffer driver, SD image assembler |
| `py/` | `zynqmini`: PYNQ-free Python layer (bitstream loading, registers, FCLK, DMA buffers, interrupts) and the open-flow `pltest` |
| `debug/` | OpenOCD configuration and GDB demo for the PS over JTAG |
| `tests/` | Board tests: DDR stability (bare-metal and Linux), HDMI capture-card check |

Status (tested on REV B, XC7Z010-1CLG400, 2026-11):
- PL: LEDs, keys, OLED, I2C EEPROM, PS-to-PL AXI, HDMI at 640x480 and 1280x720 (checked with a USB capture card).
- PS and PL together: a PL DMA block moving data to and from DDR through the PS's AXI high-performance port, controlled from Linux, with an interrupt that wakes a sleeping process (`pl/hp_dma`).
- PL Ethernet over a real cable at 1000 Mb/s: MAC front end in the PL, protocol stack in software on the PS (`pl/ple_mac`); an ARP request sent by the FPGA is answered by the peer, and the FPGA (10.0.0.2) answers the laptop's ARP, six pings and a UDP echo (counted on the board: 1 ARP reply, 6 ICMP echo replies, 1 UDP echo).
- Memory: the boot chain's DDR init passes a bare-metal 511 MiB random-pattern test and a two-core Linux memory stress (`tests/`).
- Boot: boot ROM -> open-built U-Boot SPL (hand-written PS7 init) -> U-Boot -> Linux, from SD slot 1 or from the QSPI flash (`boot/qspi`; the SD cards then need no bootloader). The kernel is built from source with a hand-written device tree (`linux/`);
  the root filesystem is either the PYNQ/Ubuntu userland or the source-built Buildroot image (`buildroot/`, Python 3 + numpy, ssh, the `zynqmini` layer and tests preinstalled).
- A/B slots: U-Boot's `boot_targets` (saved in the flash) chooses which SD slot boots; from Linux, `fw_setenv boot_targets "mmc1 mmc0"; reboot`. Checked both ways on the board.
- Toolchain: the kernel, U-Boot and root filesystem all build with the cross compiler that Buildroot builds from source (no PetaLinux/Vitis compiler); `build_all.sh` builds the whole open path into one SD image plus a QSPI image (run end to end on 2026-11-23 from the existing sources and Buildroot build: exit 0, image and flash image produced; a from-scratch run additionally spends about an hour on the toolchain).
- Verification: RTL simulations of `zm_base`, `hp_dma` and `ple_mac` (`pl/sim`, mutation-checked) and bounded formal proofs of `hp_dma`, `zm_base` and `ple_mac` (`pl/formal`); the formal run found two real DMA bugs (unaligned bursts crossing 4 KiB, `mode` read live), fixed and re-tested on hardware.
- Debugging: OpenOCD + GDB over JTAG (`debug/`): both cores, SMP mode, hardware breakpoints, loading and running a bare-metal program. Single-stepping the live SMP kernel wedged the board in two attempts and is not supported.
- Open items: the QSPI image built with the Buildroot compiler has not been flashed and boot-tested yet; USB device and host mode, and the 40-pin header with a real load, are not exercised on the open kernel (see `TESTING.md`).
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
