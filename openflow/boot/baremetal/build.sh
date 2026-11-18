#!/usr/bin/env bash
# Builds ddrtest.bin (default: short test, two random patterns; FULL_TEST=1 adds address/checkerboard patterns, ~3x longer)
# Builds ddrtest.bin (runs from high OCM at 0xFFFC0000). Needs arm-none-eabi-gcc in PATH (or set CROSS_COMPILE).
set -e
HERE=$(cd "$(dirname "$0")" && pwd); CC=${CROSS_COMPILE:-arm-none-eabi-}
mkdir -p "$HERE/build"; cd "$HERE/build"
${CC}gcc -mcpu=cortex-a9 -marm -O1 -ffreestanding -nostdlib -nostartfiles -Wl,--build-id=none -Wall -Wno-unused-function \
    ${FULL_TEST:+-DFULL_TEST} -I"$HERE/../ps7" -I"$HERE" -T "$HERE/link.ld" "$HERE/start.S" "$HERE/main.c" -o ddrtest.elf
${CC}objcopy -O binary ddrtest.elf ddrtest.bin
${CC}size ddrtest.elf | tail -1; ls -la ddrtest.bin
