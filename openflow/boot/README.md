# Open boot chain

```
boot ROM --(SD card, BOOT.BIN)--> U-Boot SPL (hand-written PS7 init) --(u-boot.img)--> U-Boot --> PYNQ Linux
```
- `build.sh`      builds `build/out/BOOT.BIN` (the SPL) and `build/out/u-boot.img` from the pinned upstream tag plus `uboot/overlay`.
- `ps7/`          the hand-written PS7 init and the trace comparison against Vivado's tables, see `ps7/README.md`.
- `uboot/`        what is added to U-Boot: device tree for the board and the init wrapper, config fragment.
- `baremetal/`    bare-metal DDR test (`build.sh`), driven by `../tests/run_ddr_test.sh`.
- `mkboot.py`     a small open BOOT.BIN assembler (byte-identical to Xilinx's bootgen for the vendor image; not needed by the U-Boot path, which produces BOOT.BIN itself).

## Installing
Copy `BOOT.BIN` and `u-boot.img` to the FAT boot partition of the SD card. KEEP the vendor `BOOT.BIN` as `BOOT.BIN.orig`:
to go back, rename it over `BOOT.BIN` (on a PC, or on the board with `sudo cp /boot/BOOT.BIN.orig /boot/BOOT.BIN`).
The SPL loads `u-boot.img` from the first FAT partition; U-Boot then runs the existing `boot.scr` and boots `image.ub` as before.

## Safe way to test a new SPL or init without touching BOOT.BIN
Link a test build at 0xFFFC0000 (CONFIG_SPL_TEXT_BASE) and start it from the running U-Boot with a one-shot `uEnv.txt`:
`dcache off; cp.b <file> 0xFFFC0000 <size>; mw.l` (arm the watchdog, see `../tests/run_ddr_test.sh`) `; go 0xFFFC0000`.
Notes from bringing this up: U-Boot maps the OCM execute-never (hence `dcache off`); the old U-Boot leaves the SCU address filter at 0,
which routes address 0 to DDR, so an SPL linked at 0 cannot be tested that way; a custom board device tree needs `bootph-all` on the
UART, SD and QSPI nodes or the SPL silently stalls (it has no serial device).
