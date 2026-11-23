# Hardware tests still to run (the board was powered off when the rest was closed out)

Everything else in `openflow/` was built and tested on the board (see the status list in `README.md`). These need hardware:

1. **QSPI image from the Buildroot-compiler build.** `build/open-image/qspi_flash.bin` (made by `build_all.sh`) has not been flashed. The flash currently holds the same bootloader built with the Vitis compiler.
   Back up first (`cat /dev/mtd0ro > mtd0.raw` on the board), flash with `boot/qspi/qspi_write.py qspi_flash.bin` (root, on the board), reset with the JTAG reset (SW1 stays on QSPI), check the UART shows
   "Trying to boot from SPI", U-Boot, then Linux. Fallback: switch SW1 to SD; the vendor image is in `~/ps3/qspi_backup` if the flash must be restored.
2. **The image from `build_all.sh`** (`build/open-image/zynqmini-open.img`, Buildroot userland with the Buildroot-built kernel): write it to a spare card, boot it from slot 2 (set `boot_targets` to `mmc1 mmc0` in the U-Boot console or with `fw_setenv`), run `/opt/zynqmini/tests/pltest_open.py`.
   (An equivalent image, built earlier with the same compiler, was booted and passed.)
3. **USB device mode**: cable the board's USB port to a PC; the NCM + ACM gadget should enumerate (the UDC reports `suspended` until a host is connected). **USB host mode**: keyboard and a flash drive.
4. **Header test with a real load**, and a visual check of the OLED after a long uptime (the 40-pin header test passes with nothing connected).
5. Re-flash the original PYNQ SD card if wanted (the slot-2 card was erased on purpose), and remove the temporary inbound firewall rule for OpenOCD (TCP 3333) on the Windows laptop.

6. **Debian image** (`debian/`, `build/debian/zynqmini-debian.img`): write to a card, boot from slot 2 (or slot 1), check: login prompt on the UART (`zynq`/`zynqmini`), DHCP lease, `ssh zynq@<ip>`, `apt update && apt install tree`, Jupyter at `http://<ip>:9090` (password `zynqmini`),
   run `notebooks/00_getting_started.ipynb` to `03_timer_interrupt.ipynb` and `python3 /usr/share/zynqmini/tests/pltest_open.py /usr/share/zynqmini/bitstreams/zm_base.bin`, `reboot` works, the first boot grows the root partition (`df -h /`),
   and the USB gadget: cable the USB port to a PC, `192.168.2.99`, serial console, `zynqmini-usb-role host` with a keyboard/flash drive.
