#!/usr/bin/env bash
# Cross-compiles memtest for the board (32-bit ARM Linux, static). Needs arm-linux-gnueabihf-gcc or arm-linux-gnueabi-gcc.
set -e
HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$HERE/build"
CC=${CC:-$(command -v arm-linux-gnueabihf-gcc || command -v arm-linux-gnueabi-gcc || echo "$HOME/Xilinx/Vitis/2024.1/gnu/aarch32/lin/gcc-arm-linux-gnueabi/bin/arm-linux-gnueabihf-gcc")}
$CC -O2 -static -pthread -o "$HERE/build/memtest" "$HERE/memtest.c"
ls -la "$HERE/build/memtest"
