# Building PYNQ for the ZYNQ MINI

Builds a PYNQ v3.1.2 SD card image for the Bochen Jingxin ZYNQ MINI (XC7Z010-1CLG400) with the
standard PYNQ `sdbuild` flow. It reuses AMD's prebuilt Ubuntu root filesystem, so there is no full rootfs rebuild.

## What is in this directory

| Path | Purpose |
|---|---|
| `ZynqMini/ZynqMini.spec` | `sdbuild` board spec (`ARCH=arm`, FPGA manager on, `xrt` package included) |
| `ZynqMini/base/base.py` | Stub `BaseOverlay` for a PS-only overlay |
| `ZynqMini/petalinux_bsp/meta-user/.../system-user.dtsi` | Device tree overrides: USB ULPI PHY, SD1 `broken-cd`, QSPI flash, Ethernet PHY node |
| `ZynqMini/petalinux_bsp/meta-user/recipes-kernel/` | Kernel config fragment `usb-gadget.cfg`: USB gadgets for ACM, ECM, NCM and RNDIS functions (Serial and Ethernet over USB) |
| `ZynqMini/packages/zynqmini_tweaks/qemu.sh` | Applies rootfs fixes inside the build chroot: Disables DHCP servers, fixes `haveged` seccomp, sets SD CID-derived Ethernet MAC |
| `build_xsa.tcl` | Vivado: PS-only design from the board preset, writes the XSA, `base.bit`, `base.hwh` |
| `overlay/build_overlay.tcl` | Vivado: LED + key overlay (two AXI GPIOs on the board interfaces) |
| `overlay/leds_keys_test.py` | Demo for above overlay |
| `overlay/pltest/` | PL self-test overlay (`./build.sh pltest`) and its on-board runner `pltest_run.py`: LEDs/keys, header, clocks, timer interrupt, DMA, EEPROM, OLED, PL Ethernet PHY |
| `overlay/hdmi_test/` | HDMI test-pattern overlay (`./build.sh hdmi`) |
| `overlay/README.md` | What each overlay and PL test checks |
| `patches/petalinux-package-bsp.patch` | Fix for a PetaLinux 2024.1 bug that breaks BSP packaging |
| `build.sh` | `xsa`, `overlay`, `pltest`, `hdmi` and `image` build steps with the required environment |
| `tests/` | Scripts to check peripherals on the board (see `tests/README.md`) |

Generated files (`*.xsa`, `base.bit`, `base.hwh`, `overlay/out/`, `build/`) are git-ignored.

## Requirements

- Ubuntu 22.04 on real hardware or a VM (not WSL2), with roughly 100 GB free and 8+ GB RAM
- Vivado, Vitis and PetaLinux **2024.1**. PYNQ v3.1.2 needs exactly this version. PYNQ 4.0+ does not support this platform
- Root access, as the rootfs stage mounts and chroots, and will not run without `sudo`
- The board files from this repository's `zynq_mini/` directory

## One-time host setup

1. **System packages** (The PetaLinux installer will softlock without these packages):

   ```
   sudo apt install -y xterm autoconf libtool texinfo zlib1g-dev build-essential \
     libncurses5-dev libncursesw5-dev gawk git diffstat unzip chrpath socat cpio python3 \
     python3-pip python3-pexpect xz-utils iputils-ping libsdl1.2-dev gcc-multilib libtool-bin lz4 zstd
   ```

2. **PetaLinux 2024.1** (Only the `arm` sources are needed):

   ```
   ./petalinux-v2024.1-final-installer.run -d ~/petalinux-2024.1 -p arm
   ```

3. **Patch PetaLinux** (Fixes broken bsp packaging in 2024.1)

From the PetaLinux install directory:

   ```
   cd ~/petalinux-2024.1 && patch -p1 < <repo>/pynq/patches/petalinux-package-bsp.patch
   ```

4. **PYNQ v3.1.2**:

   ```
   git clone --branch v3.1.2 --depth 1 https://github.com/Xilinx/PYNQ.git ~/PYNQ
   cd ~/PYNQ/sdbuild/scripts && ./setup_host.sh
   ```

   `setup_host.sh` needs `sudo`. It installs the remaining packages and builds **QEMU 5.2.0** into
   `/opt/qemu` and **crosstool-ng** into `/opt/crosstool-ng`. Ubuntu's own QEMU is 6.2 and fails
   `sdbuild`'s version check, so `build.sh` puts `/opt/qemu/bin` and `/opt/crosstool-ng/bin` first on `PATH` when building.

5. **PYNQ Source distribution and Ubuntu Jammy rootfs**:

   ```
   cd ~/PYNQ/sdbuild/prebuilt
   curl -L -o pynq_sdist.tar.gz       https://download.amd.com/opendownload/pynq/pynq-3.1.2.tar.gz
   curl -L -o pynq_rootfs.arm.tar.gz  https://download.amd.com/opendownload/pynq/jammy.arm.3.1.0.tar.gz
   ```

   (Also listed at https://www.pynq.io)

## Build

If your tools are not under the default paths, set `VIVADO_DIR`, `VITIS_DIR`, `PETALINUX_DIR` and `PYNQ_DIR`.

```
cd pynq
./build.sh xsa        # a few minutes: XSA, base.bit, base.hwh
./build.sh image      # long; prompts for sudo at the rootfs stage
```

The image is written to `~/PYNQ/sdbuild/output/ZynqMini-3.1.2.img` and should by ~8 GiB.

**After changing `ZynqMini.spec` or anything in `packages/`, run `./build.sh image --force-rootfs`.**

`make` does not treat the spec as a dependency and will finish "successfully" without rebuilding the rootfs.

**After changing `meta-user/` (device tree), use ./build.sh image --force-boot`**

This forcefully re-creates the PetaLinux project, otherwise the change will not be picked up.

## Flash and boot

1. Write the `.img` to an 8 GB or larger SD card (balenaEtcher, Raspberry Pi Imager, `dd`, etc.).
2. Put the card in **SD0**.
3. Set the BOOT switches to SD (`11`): Slide both toward the side marked "1 2".
4. Connect the **UART** port to the PC. This also powers the board. Open the CH340 serial port at 115200 8N1, no flow control, then reset or power-cycle by using the POR button, to monitor the boot process.
5. Log in as `xilinx` / `xilinx`. Jupyter is at `http://<board-ip>:9090` (password `xilinx`) once Ethernet is up.

If the console stays completely silent after a successful flash, try reseating the SD card or changing to a brand-name SD card.


## Test status

| Item | Status |
|---|---|
| Boot from SD0, FSBL, DDR (512 MB), U-Boot, Linux | Verified |
| Jupyter, PYNQ, loading overlays via FPGA Manager | Verified |
| PL LEDs and keys via custom overlay | Verified |
| SD1 (at boot or hot-plug) | Verified |
| PS LED (MIO9) and KEY1 (MIO0) through `pynq.GPIO` | Verified |
| `pynq.allocate` buffers (1 to 34 MB, cacheable and not), 200 alloc/free cycles, CMA 128 MB | Verified |
| PYNQ library test suite (`PYNQ/tests/`, mock-based) run on the board | 280 pass, 12 skipped; 13 errors w/o `pyfakefs` installed |
| QSPI as an MTD device | Verified |
| USB host, full-speed device (keyboard/mouse) | Verified |
| USB host, high-speed device (flash drive) | Verified |
| USB device mode | Verified |
| Watchdog | `cdns-wdt` present (`/dev/watchdog`, 10 s timeout); reset behaviour not tested |
| RTC | None on the board |
| USB gadget serial (CDC ACM) and Ethernet (NCM) | Verified |

Specific PL tests available in pynq/tests/README.md