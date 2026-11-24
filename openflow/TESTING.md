# Hardware tests still to run (the board was powered off when the rest was closed out)

Everything else in `openflow/` was built and tested on the board (see the status list in `README.md`). These need hardware:

1. ~~QSPI image from the Buildroot-compiler build~~ **done 2026-11-24**: flashed from Linux (`qspi_write.py`, readback matched), reset, U-Boot SPL then the open kernel booted from both SD slots. The previous flash contents are in `~/ps3/qspi_backup/mtd0_pre_buildroot_uboot.raw`.
2. ~~The image from `build_all.sh`~~ **done 2026-11-24**: booted from slot 2 (UART clean, DHCP, dropbear), `pltest_open.py` 6 PASS + OLED manual, reboot works. That card image predates zynqmini 0.2.0 and the `.pth` fix; a fresh `build_all.sh` run picks both up.
3. **USB device mode and host mode: reported OK by the user on 2026-11-24 (not re-tested by me).** Original notes: **USB device mode**: cable the board's USB port to a PC; the NCM + ACM gadget should enumerate (the UDC reports `suspended` until a host is connected). **USB host mode**: keyboard and a flash drive.
4. **Header test with a real load**, and a visual check of the OLED after a long uptime (the 40-pin header test passes with nothing connected).
5. Re-flash the original PYNQ SD card if wanted (the slot-2 card was erased on purpose), and remove the temporary inbound firewall rule for OpenOCD (TCP 3333) on the Windows laptop.

6. **Debian image** (`debian/`, `build/debian/zynqmini-debian.img`): **tested 2026-11-24 on slot 2**: boots in ~30 s, DHCP lease, ssh, `apt update` + `apt install`, Jupyter on port 9090 (HTTP 200), numpy/scipy/pandas/matplotlib + `zynqmini`, `pltest_open.py` 6 PASS (+ OLED manual), notebooks 00-03 run headless (fixed two notebook bugs and `ContigArray.free()` found by this), `reboot` works, first boot grew the root partition to 118 GB.
   Found and fixed: the GEM was renamed `end0` by udev so DHCP never ran (now `etc/systemd/network/10-zynqmini-eth0.link` keeps `eth0`). Still to test: the USB gadget with a cable (NCM `192.168.2.99`, serial console), `zynqmini-usb-role host` with a keyboard/flash drive.
