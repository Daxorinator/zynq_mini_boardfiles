# PYNQ sdbuild board spec for the Bochen Jingxin ZYNQ MINI (XC7Z010-1CLG400).
# Modelled on boards/Pynq-Z2/Pynq-Z2.spec in the PYNQ repository.
#
# - BSP is blank: sdbuild creates the PetaLinux project from the XSA in
#   petalinux_bsp/hardware_project/ (built by ../build_xsa.tcl).
# - BITSTREAM is the empty-PL bitstream from ../build_xsa.tcl; BOOT.BIN needs a file.
# - FPGA_MANAGER=1 loads overlays through the kernel FPGA manager (device tree overlays).
# - "xrt" is REQUIRED. It installs the zocl driver and sets XILINX_XRT, without which PYNQ
#   reports "No Devices Found".
ARCH_ZynqMini := arm
BSP_ZynqMini :=
BITSTREAM_ZynqMini := base/base.bit
FPGA_MANAGER_ZynqMini := 1

STAGE4_PACKAGES_ZynqMini := xrt pynq ethernet sdcardshrink zynqmini_tweaks
