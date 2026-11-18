# QSPI boot

With the boot switch on QSPI (`SW1` = 10) the boot ROM reads `BOOT.BIN` (our U-Boot SPL) from the start of the QSPI flash, the SPL loads `u-boot.img` from flash offset 0x100000,
and U-Boot then reads its environment from the flash (0xE00000) and boots like from SD: its distro boot looks at SD slot 0, then slot 1 (`boot_targets`).

- `qspi_flash.bin` = `BOOT.BIN` (built with `../mkboot.py`, bootgen-compatible header incl. the QSPI width word) padded to 0x100000, then `u-boot.img`. Build: `../build.sh`, then
  `python3 ../mkboot.py out/BOOT_QSPI.bin spl:out/spl/u-boot-spl.bin:0x0:0x0` and concatenate (see the commit that added this folder for the exact steps; `make_qspi.sh` does it).
- `qspi_write.py <image>` on the board (root): erases the needed 64 KiB blocks of `/dev/mtd0`, writes the image, reads it back and compares. Back up the flash first
  (`cat /dev/mtd0ro > mtd0.raw`; restore with the same script).
- Slot choice (A/B): `setenv boot_targets "mmc1 mmc0 ..."; saveenv` in U-Boot (or `fw_setenv` from Linux) selects which card boots; the SD cards no longer need to hold the bootloader.
