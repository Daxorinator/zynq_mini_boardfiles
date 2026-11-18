#!/usr/bin/env bash
# More PS debugging over JTAG: both cores, hardware breakpoints and single-step on the running kernel, and loading + running a bare-metal program in the OCM.
# usage: gdb_extras.sh <core0-host:port> <vmlinux> [<core1-host:port>]      (see README.md; the last part RESETS the board: it destroys the running Linux)
set -e
HERE=$(cd "$(dirname "$0")" && pwd); C0=${1:?usage: $0 core0-host:port vmlinux [core1-host:port]}; VMLINUX=${2:?}; C1=${3:-}
export PATH="$PATH:$HOME/Xilinx/Vitis/2024.1/gnu/aarch32/lin/gcc-arm-linux-gnueabi/bin:$HOME/Xilinx/Vitis/2024.1/gnu/aarch32/lin/gcc-arm-none-eabi/bin"
GDB=$(command -v arm-linux-gnueabihf-gdb || command -v arm-none-eabi-gdb || command -v gdb-multiarch)
T=$(mktemp -d)
resume_all() { for t in "$C0" ${C1:+"$C1"}; do timeout 30 timeout 90 "$GDB" -batch -nx -ex "target extended-remote $t" -ex "monitor resume" -ex "detach" >/dev/null 2>&1 || true; done; }
trap 'resume_all; rm -rf "$T"' EXIT           # never leave a core halted, whatever happened
arm-none-eabi-gcc -nostdlib -Ttext=0xFFFF0000 -o "$T/ocm_test.elf" "$HERE/ocm_test.S" && arm-none-eabi-objcopy -O binary -j .text "$T/ocm_test.elf" "$T/ocm_test.bin"
echo "=== 1. hardware breakpoint on the running kernel (core 0) ==="
timeout 90 "$GDB" -batch -nx "$VMLINUX" -ex "set pagination off" -ex "set confirm off" -ex "target extended-remote $C0" -ex "monitor halt" \
  -ex "hbreak cpu_v7_do_idle" -ex "continue" -ex "info registers pc lr" -ex "bt 4" -ex "delete" -ex "monitor resume" -ex "detach"
[ -n "$C1" ] && { echo "=== 2. core 1 ==="; timeout 90 "$GDB" -batch -nx "$VMLINUX" -ex "set pagination off" -ex "target extended-remote $C1" -ex "monitor halt" -ex "info registers pc cpsr" -ex "bt 3" -ex "monitor resume" -ex "detach"; }
echo "=== 3. load and run a bare-metal program in the OCM (MMU/caches turned off first; the board must be reset afterwards) ==="
# the program is a few words: write them with the system-bus target (physical addresses), so no Linux mapping is involved
WORDS=$(python3 -c "import struct,sys; d=open('$T/ocm_test.bin','rb').read(); d+=b'\0'*(-len(d)%4); print(' '.join('%08x' % w for w in struct.unpack('<%dI' % (len(d)//4), d)))")
EX=(); A=0xFFFF0000; for w in $WORDS; do EX+=(-ex "monitor zynq.ahb mww $A 0x$w"); A=$(printf '0x%X' $((A + 4))); done
timeout 90 "$GDB" -batch -nx -ex "set pagination off" -ex "target extended-remote $C0" -ex "monitor halt" \
  -ex "monitor zynq.core0 arm mcr 15 0 1 0 0 [expr {[zynq.core0 arm mrc 15 0 1 0 0] & ~0x1805}]" "${EX[@]}" \
  -ex "monitor zynq.ahb mdw 0xFFFF0000 5" \
  -ex "set \$pc = 0xFFFF0000" -ex "set \$cpsr = 0x1D3" -ex "monitor resume 0xFFFF0000" -ex "shell sleep 1" -ex "monitor halt" -ex "monitor zynq.core0 arm core_state" -ex "monitor reg r0" -ex "monitor reg r1" -ex "monitor reg pc" \
  -ex "monitor zynq.ahb mww 0xf8000008 0xdf0d" -ex "monitor zynq.ahb mww 0xf8000200 1" -ex "detach"
