#!/usr/bin/env bash
# Builds the open boot chain for the ZYNQ MINI: U-Boot SPL (with the hand-written ps7 init) -> BOOT.BIN, and u-boot.img.
#   ./build.sh            output in boot/build/out: BOOT.BIN, u-boot.img
# Needs: a bare-metal ARM GCC (arm-none-eabi-gcc; any recent one, e.g. Arm GNU toolchain or the one shipped in Vitis),
#        bison, flex, make, python3, curl. Set CROSS_COMPILE (default arm-none-eabi-) and PATH accordingly.
# Source: Xilinx u-boot-xlnx tag xilinx-v2024.1 (pinned by SHA-256), unmodified, plus the files in uboot/overlay.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/build}
TAG=xilinx-v2024.1
URL=https://github.com/Xilinx/u-boot-xlnx/archive/refs/tags/$TAG.tar.gz
SHA=32bcf6b792ef8c072e82ec7d0388f6d9659020bc35f9335e7fb2eff72bc819df
export CROSS_COMPILE=${CROSS_COMPILE:-arm-none-eabi-} ARCH=arm
command -v ${CROSS_COMPILE}gcc >/dev/null || { echo "no ${CROSS_COMPILE}gcc in PATH (set CROSS_COMPILE/PATH)"; exit 1; }
mkdir -p "$WORK/dl"
TAR=$WORK/dl/u-boot-xlnx-$TAG.tar.gz
[ -f "$TAR" ] || curl -sSL -o "$TAR" "$URL"
echo "$SHA  $TAR" | sha256sum -c - >/dev/null || { echo "checksum mismatch for $TAR"; exit 1; }
rm -rf "$WORK/src" "$WORK/out"; mkdir -p "$WORK/src" "$WORK/out"
tar -xzf "$TAR" -C "$WORK/src" --strip-components=1
cp -r "$HERE/uboot/overlay/." "$WORK/src/"
B=$WORK/src/board/xilinx/zynq/zynq-zynqmini
cp "$HERE/ps7/ps7_open.c" "$HERE/ps7/ps7_open.h" "$HERE/ps7/ps7_hw.c" "$HERE/ps7/ps7_ddr_table.inc" "$B/"
sed -i 's/^\tzynq-microzed.dtb \\/\tzynq-microzed.dtb \\\n\tzynq-zynqmini.dtb \\/' "$WORK/src/arch/arm/dts/Makefile"
grep -q zynq-zynqmini.dtb "$WORK/src/arch/arm/dts/Makefile"
cd "$WORK/src"
make O="$WORK/out" xilinx_zynq_virt_defconfig >/dev/null
while read -r l; do
  case "$l" in \#*|"") ;; *) k=${l%%=*}; v=${l#*=}; ./scripts/config --file "$WORK/out/.config" --set-str "${k#CONFIG_}" "$(echo "$v" | tr -d '"')";; esac
done < <(grep -E '^CONFIG_(DEFAULT_DEVICE_TREE|OF_LIST)=' "$HERE/uboot/zynqmini.config")
./scripts/config --file "$WORK/out/.config" --disable TOOLS_MKEFICAPSULE
make O="$WORK/out" olddefconfig >/dev/null
make O="$WORK/out" -j"$(nproc)" >"$WORK/build.log" 2>&1 || { tail -20 "$WORK/build.log"; exit 1; }
cp "$WORK/out/spl/boot.bin" "$WORK/out/BOOT.BIN"
echo "built:"; ls -la "$WORK/out/BOOT.BIN" "$WORK/out/u-boot.img"; md5sum "$WORK/out/BOOT.BIN" "$WORK/out/u-boot.img"
echo "install: copy BOOT.BIN and u-boot.img to the FAT boot partition of the SD card (keep the vendor BOOT.BIN as BOOT.BIN.orig)."
