# Open-source userland (Buildroot)

`./build.sh` builds, from source and without any Xilinx tool, a cross toolchain (GCC 12, glibc) and a small root filesystem for the ZYNQ MINI: BusyBox init, Dropbear (ssh, root
password `zynqmini`, DHCP on eth0, serial console on ttyPS0), Python 3 with numpy and pip, i2c-tools, usbutils, mtd-utils, iperf3, htop, nano, curl, e2fsprogs, dosfstools.
The `zynqmini` Python layer, the board tests and the open-flow bitstreams (if built) are installed in `/opt/zynqmini`, `PYTHONPATH` is set for logins, and the `zmbuf` driver is loaded at boot.

The toolchain it builds also compiles the other open-path parts, so the whole open path needs no PetaLinux/Vitis compiler (checked 2026-11-18: kernel and U-Boot built with it):
`PATH=<out>/host/bin:$PATH CROSS_COMPILE=arm-buildroot-linux-gnueabihf- ../linux/build.sh` (and the same for `../boot/build.sh`).

A/B slots: U-Boot tries the cards in the order of its `boot_targets` variable (saved in the QSPI flash). From Linux: `fw_printenv boot_targets`, `fw_setenv boot_targets "mmc1 mmc0"; reboot`
(`/etc/fw_env.config` points at the flash environment) boots slot 2 first; the boot script picks `root=/dev/mmcblk<slot>p2`, so each card is self-contained. The bootloader is in the QSPI flash
(`../boot/qspi`), so neither card has to hold it.

Image: `../linux/mkimage.py --rootfs-image <out>/images/rootfs.ext4 ...` (set `DEBUGFS=<out>/host/sbin/debugfs`).

Not in this image compared with the PYNQ image: Jupyter, pandas/scipy, the PYNQ Python library and its overlays' metadata, and the Ubuntu package manager. numpy and pip are included, so most
pure-Python packages can be installed with pip on the board.
Verified so far: the image builds, its filesystem checks clean with Buildroot's e2fsprogs, and the contents are as above; booting it on the board is still to be done (needs a spare SD card).
