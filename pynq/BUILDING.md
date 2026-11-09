# Building PYNQ for the ZYNQ MINI

Builds a PYNQ v3.1.2 SD card image for the Bochen Jingxin ZYNQ MINI (XC7Z010-1CLG400) with the
standard PYNQ `sdbuild` flow. It reuses AMD's prebuilt Ubuntu root filesystem, so there is no full rootfs rebuild.

**Status (2026-11-06):** the image builds, boots from SD0, brings up Ethernet, Jupyter and the PYNQ PL
device, and loads overlays. A custom LED + key overlay works on hardware. Other peripherals are listed under
[Test status](#test-status).

## What is in this directory

| Path | Purpose |
|---|---|
| `ZynqMini/ZynqMini.spec` | `sdbuild` board spec (`ARCH=arm`, FPGA manager on, `xrt` package) |
| `ZynqMini/base/base.py` | Stub `BaseOverlay` for the empty-PL "base" overlay |
| `ZynqMini/petalinux_bsp/meta-user/.../system-user.dtsi` | Device tree override (same mechanism as the Pynq-Z2): USB ULPI PHY, SD1 `broken-cd`, QSPI flash, Ethernet PHY node (removes a 38 s boot stall) |
| `ZynqMini/petalinux_bsp/meta-user/recipes-kernel/` | Kernel config fragment `usb-gadget.cfg`: USB gadget ACM, ECM, NCM and RNDIS functions (serial and Ethernet over the PS USB port). Built and verified (`/proc/config.gz`); NCM tested against Windows 11 |
| `ZynqMini/packages/zynqmini_tweaks/qemu.sh` | Rootfs fixes run inside the chroot: DHCP servers disabled, `haveged` seccomp fix, SD-CID-derived Ethernet MAC |
| `build_xsa.tcl` | Vivado: PS-only design from the board preset, writes the XSA, `base.bit`, `base.hwh` |
| `overlay/build_overlay.tcl` | Vivado: LED + key overlay (two AXI GPIOs on the board interfaces) |
| `overlay/leds_keys_test.py` | Demo for that overlay |
| `overlay/pltest/` | PL self-test overlay (`./build.sh pltest`) and its on-board runner `pltest_run.py`: LEDs/keys, header, clocks, timer interrupt, DMA, EEPROM, OLED, PL Ethernet PHY |
| `overlay/hdmi_test/` | HDMI test-pattern overlay (`./build.sh hdmi`), verified on a monitor |
| `overlay/README.md` | What each overlay and PL test checks |
| `patches/petalinux-package-bsp.patch` | Fix for a PetaLinux 2024.1 bug that breaks BSP packaging |
| `build.sh` | `xsa`, `overlay`, `pltest`, `hdmi` and `image` build steps with the required environment |
| `tests/` | Scripts to check peripherals on the board (see `tests/README.md`) |

Generated files (`*.xsa`, `base.bit`, `base.hwh`, `overlay/out/`, `build/`) are git-ignored.

## Requirements

- Ubuntu 22.04 on real hardware or a normal VM (not WSL2), roughly 100 GB free and 8+ GB RAM.
- Vivado, Vitis and PetaLinux **2024.1**. PYNQ v3.1.2 needs exactly this version. Do not use PYNQ 4.0
  (Vivado 2025.2, Docker, aarch64 only).
- `sudo` rights. The root filesystem stage mounts and chroots, and cannot run without a password prompt.
- The board files from this repository's `zynq_mini/` directory, used through `board.repoPaths`
  by the Tcl scripts (nothing needs copying into the Vivado install).

## One-time host setup

1. **System packages** (PetaLinux's installer refuses to run without them):

   ```
   sudo apt-get install -y xterm autoconf libtool texinfo zlib1g-dev build-essential \
     libncurses5-dev libncursesw5-dev gawk git diffstat unzip chrpath socat cpio python3 \
     python3-pip python3-pexpect xz-utils iputils-ping libsdl1.2-dev gcc-multilib libtool-bin lz4 zstd
   ```

2. **PetaLinux 2024.1, ARM sources only.** The installer's `-p` takes `arm`, not `microblaze_full`:

   ```
   ./petalinux-v2024.1-final-installer.run -d ~/petalinux-2024.1 -p arm
   ```

   (`-y` accepts the licences without showing them. Read them first if that matters to you.)

3. **Patch PetaLinux.** In 2024.1, `petalinux-package bsp` tries to create `/build` at the filesystem
   root and fails with `Unable to create directory at /build`. From the PetaLinux install directory:

   ```
   cd ~/petalinux-2024.1 && patch -p1 < <repo>/pynq/patches/petalinux-package-bsp.patch
   ```

4. **PYNQ v3.1.2** (there is no `v3.1.0` tag):

   ```
   git clone --branch v3.1.2 --depth 1 https://github.com/Xilinx/PYNQ.git ~/PYNQ
   cd ~/PYNQ/sdbuild/scripts && ./setup_host.sh
   ```

   `setup_host.sh` needs `sudo`. It installs the remaining packages and builds **QEMU 5.2.0** into
   `/opt/qemu` and **crosstool-ng** into `/opt/crosstool-ng`. Ubuntu's own QEMU is 6.2 and fails
   `sdbuild`'s version check, so `build.sh` puts `/opt/qemu/bin` and `/opt/crosstool-ng/bin` first on `PATH`.

5. **Prebuilt inputs from AMD.** These are generic, board-independent files, not our image:

   ```
   cd ~/PYNQ/sdbuild/prebuilt
   curl -L -o pynq_sdist.tar.gz       https://download.amd.com/opendownload/pynq/pynq-3.1.2.tar.gz
   curl -L -o pynq_rootfs.arm.tar.gz  https://download.amd.com/opendownload/pynq/jammy.arm.3.1.0.tar.gz
   ```

   (Also listed at https://www.pynq.io. The rootfs is about 2 GB and keeps its `jammy.arm.3.1.0` name upstream.)

## Build

If your tools are not under the default paths, set `VIVADO_DIR`, `VITIS_DIR`, `PETALINUX_DIR` and `PYNQ_DIR`.

```
cd pynq
./build.sh xsa        # a few minutes: XSA, base.bit, base.hwh
./build.sh image      # long; prompts for sudo at the rootfs stage
```

The image is written to `~/PYNQ/sdbuild/output/ZynqMini-3.1.2.img` (about 8 GB). The log shows
`[ERROR] list index out of range` from `wic`. The Makefile ignores it, and the partition table is fine.

**After changing `ZynqMini.spec` or anything in `packages/`, run `./build.sh image --force-rootfs`.** `make` does
not treat the spec as a dependency and will finish "successfully" without rebuilding the rootfs, which is how
we once shipped an image without the `xrt` package. **After changing `meta-user/` (device tree), use
`./build.sh image --force-boot`**, which also re-creates the PetaLinux project; otherwise the change is not picked up.

The LED + key overlay is separate: `./build.sh overlay` writes `overlay/out/leds_keys.{bit,hwh}`.

## Flash and boot

1. Write the `.img` to an 8 GB or larger SD card (balenaEtcher with verify, Raspberry Pi Imager, or `dd`).
   Check the checksum of your copy if the image was transferred over a network.
2. Put the card in **SD0**, the boot-capable TF slot.
3. Set the **BOOT switches to SD (`11`)**: both toward the side marked "1, 2", away from "ON KE".
4. Connect the **UART** Type-C port. It also powers the board. Open the CH340 serial port at 115200 8N1,
   no flow control, then reset or power-cycle to see the FSBL and U-Boot output.
5. Log in as `xilinx` / `xilinx`. Jupyter is at `http://<board-ip>:9090` (password `xilinx`) once Ethernet is up.

If the console stays completely silent after a good flash, reseat the card first. A flaky SD slot gave us
exactly that with a card that verified fine.

## Using PYNQ

- **Run PYNQ as root** (`sudo -i`, or the Jupyter server, which already is). As the `xilinx` user,
  `pynq.Device.devices` fails with `Could not open device with index '0'` because
  `/dev/dri/renderD128` is not accessible to it.
- Every overlay directory needs the matching `.bit`, `.hwh` and `.py` files, which the PYNQ install step copies.
  The `base` placeholder has an empty PL and only proves the load path works.
- Run the demo: copy `overlay/out/leds_keys.bit`, `leds_keys.hwh` and `overlay/leds_keys_test.py` to
  one folder on the board and run `python3 leds_keys_test.py` as root. The LEDs chase, then follow KEY2 and KEY3.

## Why the spec looks the way it does

- `BSP_ZynqMini` is blank so `sdbuild` generates the PetaLinux project from our XSA.
- The bitstream is an empty-PL design. `petalinux-package --boot --fpga` refuses to run without a bitstream file.
- `FPGA_MANAGER=1` is the PYNQ default and enables device tree overlays through the kernel FPGA manager.
- `xrt` is **required**. The `sdbuild` flow always builds the `zocl` driver and its device tree node, but the
  `xrt` package copies the driver into the rootfs and sets `XILINX_XRT=/usr`. Without it
  PYNQ prints "No devices found" and `Overlay()` raises `No Devices Found`.
- `boot_leds`, `pynq_peripherals` and `precached_metadata` from the Pynq-Z2 spec are left out
  (they are Z1/Z2-specific or only speed up first use).
- `zynqmini_tweaks` is a board-local package (`ZynqMini/packages/`). It disables `isc-dhcp-server` and
  `isc-dhcp-server6` (this board is a DHCP client only; the prebuilt rootfs ships the servers and they fail
  at every boot), adds a systemd drop-in so `haveged` stops crash-looping, and installs `zynqmini-mac.service`
  (stable MAC from the boot SD card CID); see Known issues.

## Test status

| Item | Status |
|---|---|
| Boot from SD0, FSBL, DDR (512 MB), U-Boot, Linux, PYNQ welcome | Verified |
| Ethernet (PS, ETH0) at 1 Gb/s | Verified |
| Jupyter, `pynq.Device`, loading overlays via FPGA manager | Verified |
| PL LEDs and keys through the custom overlay | Verified |
| SD1 with a card present at boot, or re-probed by hand | Verified (card enumerates, 21 MB/s read, 15 GiB SDHC) |
| PS LED (MIO9) and KEY1 (MIO0) through `pynq.GPIO`; XADC (52 C, rails sane) | Verified |
| `pynq.allocate` buffers (1 to 34 MB, cacheable and not), 200 alloc/free cycles, CMA 128 MB | Verified |
| PYNQ library test suite (`PYNQ/tests/`, mock-based) run on the board | 280 pass, 12 skipped; 13 errors only because `pyfakefs` is not installed |
| SD1 hot-plug (`broken-cd`) | Verified in the rebuilt image: a card inserted after boot is detected with no unbind/bind (15 GiB SDHC, 23.8 MB/s read) |
| QSPI as an MTD device | Verified: W25Q128 (16 MB), three partitions (`qspi-boot`, `qspi-kernel`, `qspi-bootenv`) |
| `haveged` and DHCP-server fixes (`zynqmini_tweaks`) | Verified in the rebuilt image: no failed units, `haveged` 0 restarts, DHCP servers disabled, nothing on UDP 67 |
| `chosen/pynq_board` in the rebuilt image | `ZynqMini` |
| USB host, full-speed device (keyboard/mouse) | Verified: ULPI PHY probes, port switches to host when a device is plugged in, device enumerates and creates input devices |
| USB host, high-speed device (flash drive) | Verified with a second drive (3.7 GiB, 480 Mb/s, 18.5 MB/s raw read); a first, unidentified drive failed to enumerate (see Known issues) |
| USB device mode (configfs mass storage gadget, `tests/usb_gadget_msc.sh`) | Verified: PC enumerated it, formatted and wrote a file, board read it back intact. The ACM/ECM/NCM/RNDIS functions were added later by `usb-gadget.cfg` (NCM verified, see below) |
| SD1 write | Verified: 32 MiB write + read-back identical (7.0 MB/s write) |
| Both Cortex-A9 cores, 160 MiB in-place RAM pattern and address tests | Verified (2 cores, 0.99 load balance; 0 memory errors). About 440 MB usable, 128 MB of it CMA |
| Watchdog | `cdns-wdt` present (`/dev/watchdog`, 10 s timeout); reset behaviour not tested |
| RTC | None on the board: the clock comes from NTP, so it is wrong until the network is up |
| QSPI contents (read-only dump) | Vendor factory demo: FSBL + `design_1_wrapper.bit` (XC7Z010 bitstream, 2.08 MB) + `oled.elf` (bare-metal OLED demo using the AXI GPIO driver). Kernel and bootenv partitions are erased, so QSPI boot cannot start Linux. The last 384 KB of the 16 MB flash is outside every partition and was not read |
| USB gadget serial (CDC ACM) and Ethernet (NCM) to a Windows 11 PC | Verified: COM port with an automatic `xilinx` login, `UsbNcm Host Device` adapter, 300 of 300 pings with 0 loss (0 to 4 ms), Jupyter reachable over the USB link (HTTP 302 in 10 ms) |
| PS clock reference | Fixed in the image: PYNQ assumed 50 MHz, the board has 33.333 MHz (see Known issues). After the fix every PL clock measures within 0.001 % of the requested value |
| Boot time (`systemd-analyze`) | Lease at 27 s (was 34 s), Jupyter started at 43 s (was 44 s), 56.5 s total (was 58.3 s); the rest is CPU-bound start-up of Jupyter on two Cortex-A9 cores |
| PL test overlay: LEDs/keys, clocks, timer interrupt through UIO, DMA loopback (375 to 400 MB/s) with interrupts, EEPROM (AT24C02 at 0x50), PL Ethernet PHY (RTL8211E ID) | Verified on hardware (`overlay/pltest/pltest_run.py`) |
| PL expansion header (34 signals) | Verified: every signal drives high and low, no coupling between pins (nothing plugged in) |
| OLED | Pattern written to the SSD1306 and confirmed visually (the display cannot be read back) |
| PL Ethernet data path (RGMII) | Not tested (needs a cable). The RGMII path is not built (the AXI Ethernet IP needs a licence). HDMI output is verified: 640x480 colour bars display correctly on a monitor |

## Known issues

- **SD1 does not notice a card inserted after boot.** The board has no card-detect line for the TF slots, and
  the generated device tree says `xlnx,has-cd = <0>` with no `broken-cd`, so Linux only checks at controller
  probe. Workaround on a running board (SD1 only; never touch `e0100000.mmc`, which holds the rootfs):
  `echo e0101000.mmc | sudo tee /sys/bus/platform/drivers/sdhci-arasan/{unbind,bind}` (unbind, then bind).
  Fixed in the image: `broken-cd` on `&sdhci1` in `system-user.dtsi` makes the MMC core poll, so a card inserted
  after boot appears within a few seconds. The unbind/bind workaround is only needed on older images.
- **PYNQ assumed the wrong PS clock (fixed).** `pynq/ps.py` hard-codes a 50 MHz PS reference for Zynq-7000
  (`_ClocksZynq.DEFAULT_SRC_CLK_MHZ`), which is right for the PYNQ-Z1/Z2 but not here: this board's PS_CLK is 33.3333 MHz
  (IO PLL x30 = 1000 MHz, ARM PLL x40 = 1333 MHz). PYNQ therefore computed an IO PLL of 1500 MHz, reported FCLKs 1.5x
  too high and, worse, programmed the dividers from the overlay's `.hwh` so a requested 100 MHz FCLK0 really ran at
  66.7 MHz. `zynqmini_tweaks/qemu.sh` now sets the default to 33.333 in the installed `ps.py` (and fails the build if the
  patch does not apply). Found by measuring the PL clocks with an RTL frequency meter against FCLK0.
- **Occasional `Wrong NTH SIGN` from the NCM gadget** (`skblen 1537` and `1025`): the Windows NCM driver sometimes
  sends a 32-bit-format NTB (`ncmh`) although the gadget only offers 16-bit. The gadget drops that one frame (seen
  with mDNS multicast). Harmless: no losses in 600+ pings or 35 downloads of 3 MB at about 20 MB/s.
- **One NCM bulk stall, seen once.** After a long idle, the first multi-hundred-KB download from the board stopped at
  exactly 256 KiB; the PC stopped polling the bulk IN endpoint (about 40 transfers queued on the board, UDC still
  `configured`, nothing in either kernel log). A 2 s UDC unbind/rebind did not clear it; a 6 s unbind did (Windows
  re-enumerated). Not reproduced in 40 further downloads or after a reboot. Workaround:
  `echo "" > /sys/kernel/config/usb_gadget/zynqmini_net/UDC; sleep 6; echo ci_hdrc.0 > .../UDC`.
- **Default credentials and SSH keys.** The image uses stock PYNQ accounts: user `xilinx`, password `xilinx`
  (also the Jupyter password). Change them before exposing the board to a network. No SSH host keys are shipped;
  each board generates its own on first boot (`zynqmini-sshkeys.service`).
- **The serial gadget logs in as `xilinx` without a password**, like the UART console (stock PYNQ behaviour). Anyone
  who can plug a cable in gets a shell.
- **USB gadget stalls in OTG mode (fixed with a software role switch).** With `dr_mode` unset (OTG) and a gadget bound,
  the Ethernet-over-USB link died at random, 9 to 165 s after binding, in both directions, with the UDC still
  `configured` and no kernel message: controller interrupts stopped, FRINDEX froze, and every ULPI register read
  timed out (the USB3320 clock was gone). Rebinding the UDC revived it briefly. `dr_mode = "peripheral"` held 17+
  minutes. The fix keeps host and device: `dr_mode = "otg"; usb-role-switch;` in `&usb0` (no kernel patch needed;
  `CONFIG_USB_ROLE_SWITCH` was already on). The role is then set in
  `/sys/class/usb_role/ci_hdrc.0-role-switch/role`, wrapped by `zynqmini-usb-role host|device|none|status`
  (boot default: **device** with a serial+NCM gadget, 192.168.2.99/24 (the PYNQ default address, moved here from the stock `eth0:1` alias, which the image removes), via `zynqmini-usb-gadget.service`; device mode never drives VBUS so a PC cable is safe at boot; for a keyboard/drive run `zynqmini-usb-role host` with the PC cable out). Mechanism not proven beyond "hardware ID/VBUS sensing off
  fixes it". Gotchas: writing `device` while already in the gadget role does nothing (driver quirk), so the helper goes
  host then device (about 6 s, `timeout waiting for 00000800 in OTGSC` is harmless); after any role change the gadget
  must be rebound or the PC link stays dead (the helper does that); host mode drives VBUS, so unplug the PC cable
  before switching to host. Host mode with a full-speed keyboard verified on the role-switch kernel; a flash drive was
  not retested there. Never write to the ULPI viewport (`0x170`) on a stalled PHY: it leaves the controller stuck and
  Windows reports "device malfunctioned".
  Board wiring (from the schematic, page 10; not verified on hardware): the PHY's VBUS pin is fed from the board 5 V rail
  (R68), not the connector, so VBUS plug/unplug is never sensed and only ID can drive automatic roles; `USB_ID` goes to
  the Type-C CC pins with no external pull. Tested with an A-to-C cable only.
- **USB host: some high-speed drives may not enumerate.** Without `usb-phy` in the device tree the controller never
  probed; the ULPI PHY node and `usb-phy` in `system-user.dtsi` (copied from the Pynq-Z2) fix that. With them the
  port comes up as a device and switches to host by itself when a device is plugged in (`dr_mode` stays unset, as on
  the Pynq-Z2). A full-speed keyboard/mouse and a second high-speed flash drive both work. One other flash drive
  failed: `device not accepting address 3, error -110`, then `device descriptor read/8, error -71`, then
  `unable to enumerate USB device`. That drive is the likely cause (the board enumerates others at 480 Mb/s), but
  it was not tried on another host, so a flaky Type-C to A adapter or cable is not ruled out. If a drive of yours
  does this, test it elsewhere first.
- (Fixed) `cannot find modalias for /axi/spi@e000d000/flash@0` / `Failed to create SPI device` at boot, and an empty
  `/proc/mtd`. The generated flash node had partitions but no `compatible` and no `reg`; `&flash0` in
  `system-user.dtsi` (`jedec,spi-nor`) fixes it and the flash now shows up as three MTD partitions.
- `haveged` crash-looped (`status=31/SYS`). The stock unit's seccomp `SystemCallFilter` does not allow `uname`,
  which armhf glibc calls at startup, so the kernel kills it. Fixed with a drop-in
  (`SystemCallFilter=uname`); verified (0 restarts), and the same drop-in is in the image via `zynqmini_tweaks`.
- `isc-dhcp-server` / `isc-dhcp-server6` fail at every boot (no interface configured). Disabled on the board and in
  `zynqmini_tweaks`; the board stays a DHCP client.
- **38 s stall in kernel boot (fixed in the device tree).** The log was silent between "CAN device driver
  interface" (1.9 s) and the `macb` probe line (40 s) on every boot, and the console visibly paused there. The
  generated device tree gives the Ethernet controller no `phy-handle` and no `mdio` child, so `macb` falls back
  to scanning all 32 MDIO addresses at probe time, and that scan blocks the whole kernel init thread. Describing
  the PHY (RTL8211E at MDIO address 0) in `system-user.dtsi` removes the scan: the `macb` line now appears at
  2.0 s and the board is reachable after about 56 s instead of about 95 s. Found by elimination
  (`initcall_blacklist=xcan_driver_init` changed nothing; re-running the `macb` probe at runtime takes 0.3 s; this
  kernel has no tracing, so `initcall_debug` shows nothing for built-in drivers), then confirmed with a patched
  `image.ub`. An already-flashed card can be fixed without a rebuild by rebuilding its FIT with the extra device
  tree nodes (extract the kernel and DTB with `dumpimage`, apply the `phy-handle`/`mdio` nodes with `fdtoverlay`,
  pad with `dtc -p 0x1000`, repack with `mkimage -f`); a new image build includes it.
- **Ethernet MAC is random at every boot (old images).** The board has no programmed MAC and no per-chip ID
  that Linux can read (`/proc/cpuinfo` Serial is all zeros; the flash unique ID and the Zynq Device DNA are not
  exposed), so U-Boot logs `using random MAC address` and the DHCP lease changes. `zynqmini_tweaks` now installs
  `zynqmini-mac.service`, which derives a stable locally administered MAC from the CID of the SD card the system
  booted from (`zynqmini-mac --print` shows it). The address follows the card: reflashing the same card keeps it,
  another card gets another one. Verified on a running board (the same script and unit installed by hand on the
  old image): the service sets `eth0` before `ifup@eth0` and `networking` start, and the board kept its address.
  Not yet verified from a freshly built image. Trying to pin the MAC from U-Boot (`ethaddr=` in `uEnv.txt`) did
  not work: the DT still got a random one.
- `pynq/tests` shipped on the board (and `PYNQ/pynq/tests`) is the old Z1-style interactive suite and is not useful
  here. Use the mock suite in the PYNQ repo's top-level `tests/`; it needs `pyfakefs` for 13 tests.
- The PetaLinux build output `images/linux/system.dtb` once came out with `chosen/pynq_board = "None"`, although
  the image that boots reports `ZynqMini`. Cause not traced (a later `petalinux-build` without `PYNQ_BOARDNAME` in
  the environment is the likely suspect). After any rebuild, check `cat /proc/device-tree/chosen/pynq_board`.
- `zocl-drm ... error -ENXIO: IRQ index 0 not found` in `dmesg` is expected: with the FPGA manager PYNQ
  uses the polling `zocl` variant, which has no interrupt.
- `/sys/class/fpga_manager/fpga0/state` can read `unknown` when the PL was configured by the FSBL at boot. It
  becomes `operating` after an overlay is loaded.

## Releasing the PYNQ build

The repository deliberately contains **no binaries** from the build. Releases attach them as GitHub release assets:

- `ZynqMini-3.1.2.img.zip` (the 8 GB SD card image, zipped to about 1.7 GiB, under GitHub's 2 GiB per-file limit),
  flashed with Balena Etcher / Raspberry Pi Imager / `dd` after unzipping.
- `zynq_mini_boardfiles.zip` (the Vivado board files from `zynq_mini/`).
- `SHA256SUMS`.

The image is a derivative of the stock PYNQ image (Ubuntu rootfs, AMD PetaLinux kernel and boot files), so it
carries the licences of those components.
