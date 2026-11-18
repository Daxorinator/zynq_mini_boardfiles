#!/usr/bin/env bash
# Builds the open Linux for the ZYNQ MINI from source: kernel (zImage), device tree, modules and the zmbuf driver.
#   ./build.sh          output in linux/build/out: zImage, zynq-zynqmini.dtb, modules.tgz (to unpack in the rootfs /lib), zmbuf.ko
# Needs an ARM Linux cross compiler (arm-linux-gnueabihf-gcc; the one in the Vitis install or the distro's), make, bc, flex, bison,
# libssl-dev, curl, dtc. Source: Xilinx linux-xlnx tag xilinx-v2024.1 (SHA-256 pinned), unmodified, plus linux/zynqmini_defconfig,
# linux/dts/zynq-zynqmini.dts (hand-written) and linux/zmbuf.
set -e
HERE=$(cd "$(dirname "$0")" && pwd); WORK=${WORK:-$HERE/build}
TAG=xilinx-v2024.1; URL=https://github.com/Xilinx/linux-xlnx/archive/refs/tags/$TAG.tar.gz
SHA=5cf7cf532f7d5877ff14c131792808cb00f451269412f215f302f9111a86c8be
export ARCH=arm CROSS_COMPILE=${CROSS_COMPILE:-arm-linux-gnueabihf-}
command -v ${CROSS_COMPILE}gcc >/dev/null || { echo "no ${CROSS_COMPILE}gcc in PATH (set CROSS_COMPILE/PATH)"; exit 1; }
mkdir -p "$WORK/dl"; TAR=$WORK/dl/linux-xlnx-$TAG.tar.gz
[ -f "$TAR" ] || curl -sSL -o "$TAR" "$URL"
echo "$SHA  $TAR" | sha256sum -c - >/dev/null || { echo "checksum mismatch for $TAR"; exit 1; }
if [ ! -d "$WORK/src" ]; then mkdir -p "$WORK/src"; tar -xzf "$TAR" -C "$WORK/src" --strip-components=1; fi
OUT=$WORK/kout; mkdir -p "$OUT" "$WORK/out"
cp "$HERE/zynqmini_defconfig" "$WORK/src/arch/arm/configs/zynqmini_defconfig"
make -C "$WORK/src" O="$OUT" zynqmini_defconfig >/dev/null
make -C "$WORK/src" O="$OUT" -j"$(nproc)" zImage modules > "$WORK/build.log" 2>&1 || { tail -20 "$WORK/build.log"; exit 1; }
rm -rf "$WORK/stage"; mkdir -p "$WORK/stage"
make -C "$WORK/src" O="$OUT" INSTALL_MOD_PATH="$WORK/stage" modules_install >> "$WORK/build.log" 2>&1
cp -r "$HERE/zmbuf" "$WORK/zmbuf_build"
make -C "$OUT" M="$WORK/zmbuf_build" src="$WORK/zmbuf_build" modules >> "$WORK/build.log" 2>&1
REL=$(ls "$WORK/stage/lib/modules")
mkdir -p "$WORK/stage/lib/modules/$REL/extra"; cp "$WORK/zmbuf_build/zmbuf.ko" "$WORK/stage/lib/modules/$REL/extra/"
depmod -b "$WORK/stage" "$REL" 2>/dev/null || true
# device tree: preprocess with the kernel's include files, compile with dtc
cpp -nostdinc -I "$WORK/src/arch/arm/boot/dts/xilinx" -I "$WORK/src/arch/arm/boot/dts" -I "$WORK/src/include" -undef -x assembler-with-cpp -D__DTS__ \
    "$HERE/dts/zynq-zynqmini.dts" 2>/dev/null | dtc -I dts -O dtb -@ -o "$WORK/out/zynq-zynqmini.dtb" - 2>/dev/null
cp "$OUT/arch/arm/boot/zImage" "$WORK/out/zImage"; cp "$WORK/zmbuf_build/zmbuf.ko" "$WORK/out/zmbuf.ko"
tar -C "$WORK/stage/lib" -czf "$WORK/out/modules.tgz" modules
echo "built kernel release $REL:"; ls -la "$WORK/out"
