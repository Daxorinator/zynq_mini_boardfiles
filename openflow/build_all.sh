#!/usr/bin/env bash
# Builds the whole open path from a clean checkout into build/open-image/zynqmini-open.img (about 1-2 hours, mostly the toolchain and kernel):
#   1. PL bitstreams (Yosys + nextpnr-xilinx)      pl/build.sh        needs openXC7 + oss-cad-suite (see pl/env.sh)
#   2. cross toolchain + root filesystem            buildroot/build.sh needs only host build tools
#   3. U-Boot SPL / U-Boot, kernel, DTB, zmbuf      boot/build.sh, linux/build.sh   (compiled with the toolchain from step 2)
#   4. the SD image                                 linux/mkimage.py, plus a QSPI image (boot/qspi/make_qspi.sh)
# Write the result to a card with:  dd if=build/open-image/zynqmini-open.img of=/dev/sdX bs=4M conv=fsync status=progress
set -e
HERE=$(cd "$(dirname "$0")" && pwd); O=$HERE/build/open-image; mkdir -p "$O"
PROJECTS=${PROJECTS:-"hp_dma zm_base ple_mac"}
[ "${SKIP_PL:-0}" = 1 ] || for p in $PROJECTS; do "$HERE/pl/build.sh" "$p"; done     # SKIP_PL=1 reuses the bitstreams already in pl/build
"$HERE/buildroot/build.sh"
BR=${WORK_BR:-$HERE/build/buildroot/out}
export PATH="$BR/host/bin:$PATH" CROSS_COMPILE=arm-buildroot-linux-gnueabihf-
"$HERE/boot/build.sh"; "$HERE/boot/qspi/make_qspi.sh"
"$HERE/linux/build.sh"
DEBUGFS="$BR/host/sbin/debugfs" python3 "$HERE/linux/mkimage.py" --rootfs-image "$BR/images/rootfs.ext4" \
  --boot-bin "$HERE/boot/build/out/BOOT.BIN" --u-boot-img "$HERE/boot/build/out/u-boot.img" --kernel-dir "$HERE/linux/build/out" --out "$O/zynqmini-open.img"
cp "$HERE/boot/build/out/qspi_flash.bin" "$O/"
if [ "${DEBIAN:-0}" = 1 ]; then "$HERE/debian/build.sh"; cp "$HERE/build/debian/zynqmini-debian.img" "$O/"; fi     # optional: DEBIAN=1 also builds the Debian image (an hour of qemu time)
ls -la "$O"
