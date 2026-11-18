#!/usr/bin/env bash
# GDB session against OpenOCD (running where the JTAG cable is). usage: gdb_demo.sh <host[:port]> [vmlinux]
#   - peeks at the SLCR and the PL register window while the system runs (non-intrusive),
#   - halts CPU 0 for a moment, shows where it is (with kernel symbols if vmlinux is given), then resumes.
# Needs arm-linux-gnueabihf-gdb (or gdb-multiarch) in PATH.
set -e
HOSTPORT=${1:?usage: $0 host[:port] [vmlinux]}; case "$HOSTPORT" in *:*) ;; *) HOSTPORT=$HOSTPORT:3333;; esac
VMLINUX=${2:-}
export PATH="$PATH:$HOME/Xilinx/Vitis/2024.1/gnu/aarch32/lin/gcc-arm-linux-gnueabi/bin:$HOME/Xilinx/Vitis/2024.1/gnu/aarch32/lin/gcc-arm-none-eabi/bin"
GDB=$(command -v arm-linux-gnueabihf-gdb || command -v arm-none-eabi-gdb || command -v gdb-multiarch)
exec "$GDB" -batch -nx ${VMLINUX:+"$VMLINUX"} \
  -ex "set pagination off" -ex "set confirm off" \
  -ex "target extended-remote $HOSTPORT" \
  -ex "echo \n--- JTAG chain / targets ---\n" -ex "monitor targets" \
  -ex "echo \n--- non-intrusive reads (CPUs keep running) ---\n" \
  -ex "monitor zynq.ahb mdw 0xf8000258" -ex "monitor zynq.ahb mdw 0xf800025c" -ex "monitor zynq.ahb mdw 0xf8000100" -ex "monitor zynq.ahb mdw 0xf8007080" \
  -ex "echo \n--- halt CPU 0, look around, resume ---\n" \
  -ex "monitor halt" -ex "info registers pc sp lr cpsr" -ex "x/6i \$pc" ${VMLINUX:+-ex "bt 6"} \
  -ex "monitor resume" -ex "detach"
