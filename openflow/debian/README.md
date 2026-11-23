# Debian userland for the open kernel

A full Debian 12 (bookworm, armhf) system on the open kernel from `../linux`: systemd, OpenSSH, `apt` with the whole Debian archive, a compiler, Python 3.11 with numpy, scipy, pandas, matplotlib and scikit-learn,
Jupyter Notebook, the USB gadget (serial console + Ethernet over the Type-C port) and the usual network services. The hardware is driven by `zynqmini` (`../py`), not PYNQ.

## Build
`./build.sh` (stages `tools base packages configure image`, each resumable from a snapshot in `../build/debian`). It needs `sudo` (chroot and mounts), qemu-user with binfmt for armhf (`/proc/sys/fs/binfmt_misc/qemu-arm`)
and network access to the Debian mirror; nothing is installed on the host (`debootstrap` and the archive keyring are fetched from the Debian archive over HTTPS and unpacked in the work directory). The package installation runs under qemu
and takes a while (about an hour). Output: `../build/debian/rootfs.ext4` and, if the open kernel and boot files are built (`../linux/build.sh`, `../boot/build.sh`, `../pl/build.sh`), `../build/debian/zynqmini-debian.img`
(5 GiB root partition; the first boot grows it to the whole card). Write it to a card with `dd`, boot it from slot 1, or from slot 2 with `boot_targets` (`../buildroot/README.md`).

## What is in it
- **System:** systemd 252, OpenSSH, ifupdown + DHCP on eth0, `systemd-timesyncd` and `fake-hwclock` (the board has no battery-backed clock, and apt rejects a stale clock), `haveged` (with the armhf seccomp fix), `apt` (docs and man pages are excluded to save space; automatic apt timers are masked).
- **Users:** `zynq` (sudo, password `zynqmini`) and `root` (password `zynqmini`, console only: ssh root login with a password is off). **Change both passwords.** The Jupyter password is `zynqmini` as well (`jupyter notebook password` changes it).
- **Network:** eth0 by DHCP with a stable MAC derived from the card's CID (`zynqmini-mac`, so a card keeps its lease); the USB gadget `zynqmini-usb-gadget` brings up a serial console (ttyGS0 getty) and NCM Ethernet, board = 192.168.2.99/24, PC = 192.168.2.1/24;
  `zynqmini-usb-role host|device` switches the port (keyboard or drive in host mode). SSH host keys are generated on the first boot.
- **Jupyter:** `jupyter.service`, port 9090, runs as root (notebooks need `/dev/mem` and the FPGA manager); notebooks are in `/home/zynq/notebooks` (getting started, clocks, DMA, timer interrupt).
- **Hardware:** `import zynqmini` (installed system-wide), bitstreams and register maps in `/usr/share/zynqmini/bitstreams`, tests in `/usr/share/zynqmini/tests`, the `zmbuf` kernel module loaded at boot.
- **Not included:** PYNQ itself (`pynq.Overlay`, its notebooks and overlay metadata) and the Xilinx `xlnk`/`zocl` drivers it needs; `zynqmini.Overlay` and `HpDma` cover the same workflow with JSON register maps.

## Status
Built and checked offline (see `../TESTING.md` for what is verified and what still needs the board). Booting it on the board and running the notebooks is not done yet.
