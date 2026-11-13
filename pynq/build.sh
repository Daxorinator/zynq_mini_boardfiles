#!/bin/bash
# Build helper for the ZYNQ MINI PYNQ image.
#
#   ./build.sh xsa                    PS-only design -> XSA, base.bit, base.hwh (Vivado)
#   ./build.sh overlay                LED + key overlay -> overlay/out/* (Vivado)
#   ./build.sh pltest                 PL self-test overlay -> overlay/out/pltest.* (Vivado)
#   ./build.sh hdmi                   HDMI test-pattern overlay -> overlay/out/hdmi_test.* (Vivado)
#   ./build.sh image                  PYNQ sdbuild -> $PYNQ_DIR/sdbuild/output/ (needs sudo, ~10-30 min with prebuilt rootfs)
#   ./build.sh image --force-rootfs   forcibly rerun the rootfs stage (use after changing ZynqMini.spec or packages/)
#   ./build.sh image --force-boot     forcibly re-create the PetaLinux project and boot files, then the rootfs (use after changing meta-user / device tree files)
set -euo pipefail

# these can be overriden using environment variables or by changing below
# it just assumes a standard Vitis + PetaLinux install in ~/Xilinx/
# and also assumes you're working out of ~/zynq_mini_boardfiles/pynq or similar
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
VIVADO_DIR="${VIVADO_DIR:-$HOME/Xilinx/Vivado/2024.1}"
VITIS_DIR="${VITIS_DIR:-$HOME/Xilinx/Vitis/2024.1}"
PETALINUX_DIR="${PETALINUX_DIR:-$HOME/petalinux-2024.1}"
PYNQ_DIR="${PYNQ_DIR:-$HOME/PYNQ}"

# QEMU 5.2.0 and crosstool-ng (from sdbuild/scripts/setup_host.sh) must be on path before /usr/bin, which on many systems contains a newer QEMU install that fails sdbuild's version check
export PATH=/opt/qemu/bin:/opt/crosstool-ng/bin:$PATH

case "${1:-}" in
  xsa)
    source "$VIVADO_DIR/settings64.sh"
    cd "$HERE" && vivado -mode batch -source build_xsa.tcl -tclargs "$REPO"
    ;;
  overlay)
    source "$VIVADO_DIR/settings64.sh"
    cd "$HERE/overlay" && vivado -mode batch -source build_overlay.tcl -tclargs "$REPO"
    ;;
  pltest)
    source "$VIVADO_DIR/settings64.sh"
    cd "$HERE/overlay/pltest" && vivado -mode batch -nojournal -nolog -source build_pltest.tcl -tclargs "$REPO" "${2:-4}"
    ;;
  hdmi)
    source "$VIVADO_DIR/settings64.sh"
    cd "$HERE/overlay/hdmi_test" && vivado -mode batch -nojournal -nolog -source build_hdmi_test.tcl -tclargs "$REPO" "${2:-4}"
    ;;
  image)
    for f in pynq_sdist.tar.gz pynq_rootfs.arm.tar.gz; do
      [ -f "$PYNQ_DIR/sdbuild/prebuilt/$f" ] || { echo "missing $PYNQ_DIR/sdbuild/prebuilt/$f (see BUILDING.md)"; exit 1; }
    done
    [ -f "$HERE/ZynqMini/petalinux_bsp/hardware_project/ZynqMini.xsa" ] || { echo "run ./build.sh xsa first"; exit 1; }
    # the vendor settings scripts are not safe under set -eu, and PetaLinux's settings.sh
    # treats positional arguments as a project path, so clear them while sourcing
    shift
    OPTS=("$@"); set --
    set +eu
    source "$VIVADO_DIR/settings64.sh"
    source "$VITIS_DIR/settings64.sh" >/dev/null 2>&1
    source "$PETALINUX_DIR/settings.sh" >/dev/null 2>&1
    set -eu
    command -v petalinux-build >/dev/null || { echo "PetaLinux settings did not load"; exit 1; }
    export PATH=/opt/qemu/bin:/opt/crosstool-ng/bin:$PATH
    for opt in "${OPTS[@]}"; do
      case "$opt" in
        --force-rootfs) rm -f "$PYNQ_DIR/sdbuild/build/ZynqMini.tar.gz" ;;
        --force-boot)   # re-create the PetaLinux project so meta-user is picked up
                        rm -rf "$PYNQ_DIR/sdbuild/build/ZynqMini" "$PYNQ_DIR/sdbuild/output/boot/ZynqMini"
                        rm -f  "$PYNQ_DIR/sdbuild/build/ZynqMini.tar.gz" ;;
        *) echo "unknown option $opt"; exit 1 ;;
      esac
    done
    cd "$PYNQ_DIR/sdbuild"
    make BOARDDIR="$HERE" BOARDS=ZynqMini
    ;;
  *)
    sed -n '2,16p' "${BASH_SOURCE[0]}"; exit 1 ;;
esac
