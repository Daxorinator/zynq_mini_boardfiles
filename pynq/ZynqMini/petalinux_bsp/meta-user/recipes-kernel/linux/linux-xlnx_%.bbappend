FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://bsp.cfg"
KERNEL_FEATURES:append = " bsp.cfg"

# USB gadget functions beyond mass storage (serial and Ethernet over the PS USB port in device mode).
SRC_URI:append = " file://usb-gadget.cfg"
