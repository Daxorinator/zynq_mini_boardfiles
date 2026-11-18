# Debugging the PS over JTAG with OpenOCD and GDB (open tools)

The on-board FT232H JTAG port exposes the ARM DAP (both Cortex-A9 cores) and the PL TAP. `zynqmini.cfg` is an OpenOCD configuration for it. Verified on the board (2026-11-18, OpenOCD 0.12.0+dev on Windows with the cable, ARM GDB from Vitis on the Linux VM over the network):
attach to the chain (PL TAP + ARM DAP), non-intrusive reads of SLCR registers while Linux runs, halt of core 0 (found in `cpu_v7_do_idle`, symbolised with the
kernel's `vmlinux`, backtrace through `cpuidle_enter`/`do_idle`), resume and detach. The PS reset (`reset-ps`) was done through the same AHB path.
Not tried: core 1, breakpoints/single-step, loading bare-metal programs with `load`, and the SMP target mode.

On the machine with the cable (needs a libusb/WinUSB driver on the FT232H; on Windows the inbound TCP port 3333 also needs a firewall rule, so remove it afterwards: the port gives unauthenticated control of the CPU): `openocd -f zynqmini.cfg -c "bindto 0.0.0.0"` (or without `bindto` to stay local).
Then `./gdb_demo.sh <host[:3333]> [vmlinux]`: reads SLCR registers (`monitor zynq.ahb mdw`) while the system runs, halts CPU 0, shows registers and instructions (with kernel
symbols if given the `vmlinux` from the kernel build), and resumes. `monitor reset-ps` (an OpenOCD Tcl proc in the config) resets the whole PS like the reset button (writes SLCR PSS_RST_CTRL).
Bare-metal programs (for example `../boot/baremetal`) can be loaded into the high OCM with GDB's `load` and run from there.
