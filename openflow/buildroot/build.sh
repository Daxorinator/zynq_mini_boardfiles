#!/usr/bin/env bash
# Builds the open-source userland: a cross toolchain (GCC, glibc) and a root filesystem (BusyBox, Dropbear, Python 3 + numpy, ...) from source with Buildroot.
#   ./build.sh            output in $WORK/out/images/rootfs.ext4 and the toolchain in $WORK/out/host (default WORK=boot dir's ../build/buildroot)
# Needs only a host C/C++ toolchain, make, wget/curl, python3, rsync, cpio, unzip, bc (see Buildroot's requirements). Takes about 30-60 minutes.
set -e
HERE=$(cd "$(dirname "$0")" && pwd); WORK=${WORK:-$HERE/../build/buildroot}
VER=2024.02.9; SHA=bed9ee669f51ea71a969409b8e06a4e4b3d5a742c5e0baea89f7811fcb8ca7fa
mkdir -p "$WORK/dl"; T=$WORK/dl/buildroot-$VER.tar.xz
[ -f "$T" ] || curl -sSL -o "$T" https://buildroot.org/downloads/buildroot-$VER.tar.xz
echo "$SHA  $T" | sha256sum -c - >/dev/null || { echo "checksum mismatch for $T"; exit 1; }
[ -d "$WORK/src" ] || { mkdir -p "$WORK/src"; tar -xf "$T" -C "$WORK/src" --strip-components=1; }
make -C "$WORK/src" O="$WORK/out" BR2_EXTERNAL="$HERE" zynqmini_defconfig >/dev/null
make -C "$WORK/out" -j"$(nproc)"
echo "rootfs: $WORK/out/images/rootfs.ext4   toolchain: $WORK/out/host/bin/arm-buildroot-linux-gnueabihf-"
