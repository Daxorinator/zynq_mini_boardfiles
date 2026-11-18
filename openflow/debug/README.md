# Debugging the PS over JTAG with OpenOCD and GDB (open tools)

The on-board FT232H JTAG port exposes the ARM DAP (both Cortex-A9 cores) and the PL TAP. `zynqmini.cfg` is an OpenOCD configuration for it. The configuration
parses with the OpenOCD in oss-cad-suite; attaching to the hardware has not been tested from this folder (the cable is on a Windows laptop and exposing the
debug port to the network needs the owner's approval).

On the machine with the cable (needs a libusb/WinUSB driver on the FT232H): `openocd -f zynqmini.cfg -c "bindto 0.0.0.0"` (or without `bindto` to stay local).
Then `./gdb_demo.sh <host[:3333]> [vmlinux]`: peeks at SLCR registers while the system runs, halts CPU 0, shows registers and instructions (with kernel
symbols if given the `vmlinux` from the kernel build), and resumes. `monitor reset-ps` resets the whole PS like the reset button (writes SLCR PSS_RST_CTRL).
Bare-metal programs (for example `../boot/baremetal`) can be loaded into the high OCM with GDB's `load` and run from there.
