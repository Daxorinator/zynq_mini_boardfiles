# Debugging the PS over JTAG with OpenOCD and GDB (open tools)

The on-board FT232H JTAG port exposes the ARM DAP (both Cortex-A9 cores) and the PL TAP. `zynqmini.cfg` is an OpenOCD configuration for it. Verified on the board (2026-11-18, OpenOCD 0.12.0+dev on Windows with the cable, ARM GDB from Vitis on the Linux VM over the network):
attach to the chain (PL TAP + ARM DAP), non-intrusive reads of SLCR registers while Linux runs, halt of core 0 (found in `cpu_v7_do_idle`, symbolised with the
kernel's `vmlinux`, backtrace through `cpuidle_enter`/`do_idle`), resume and detach. The PS reset (`reset-ps`) was done through the same AHB path.
Also verified (`gdb_extras.sh`, 2026-11-18, OpenOCD with one GDB port per core: core 0 on 3333, core 1 on 3334, no `target smp`):
core 1 halt, registers and backtrace while Linux runs; a hardware breakpoint on a kernel function (`hbreak cpu_v7_do_idle`, hit with a backtrace, then resumed); and loading a program into the
high OCM through the system-bus target (physical addresses), turning off the MMU and caches with a CP15 write and running it (`ocm_test.S`: r0 = marker, r1 counts; read back with `monitor reg`).
That last step destroys the running Linux, so the script ends with a PS reset.
Caveats found: GDB's register cache is stale after `monitor` commands (use `monitor reg ...`); connecting to a core's GDB port halts it; always resume before disconnecting. **Single-stepping (`stepi`)
the live SMP kernel left the board unresponsive (the kernel answered ping but not ssh until reset) in two attempts, so the script does not do it.** SMP target mode (`target smp zynq.core0 zynq.core1` in the OpenOCD config, one GDB port): one connection halts both cores together, registers and backtrace are read, a single `monitor resume` restarts both,
and the board stays alive afterwards (tested 2026-11-18; GDB shows one thread, since OpenOCD has no thread awareness for the kernel here). Not tried: watchpoints, Linux thread awareness.

On the machine with the cable (needs a libusb/WinUSB driver on the FT232H; on Windows the inbound TCP port 3333 also needs a firewall rule, so remove it afterwards: the port gives unauthenticated control of the CPU): `openocd -f zynqmini.cfg -c "bindto 0.0.0.0"` (or without `bindto` to stay local).
Then `./gdb_demo.sh <host[:3333]> [vmlinux]`: reads SLCR registers (`monitor zynq.ahb mdw`) while the system runs, halts CPU 0, shows registers and instructions (with kernel
symbols if given the `vmlinux` from the kernel build), and resumes. `monitor reset-ps` (an OpenOCD Tcl proc in the config) resets the whole PS like the reset button (writes SLCR PSS_RST_CTRL).
Bare-metal programs (for example `../boot/baremetal`) can be loaded into the high OCM with GDB's `load` and run from there.
