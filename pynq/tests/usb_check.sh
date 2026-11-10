#!/bin/bash
# Check the PS USB 2.0 port (USB3320 ULPI PHY on MIO28-39, PHY reset MIO46). This is the middle Type-C connector.
#
# Before running: plug a USB device (keyboard, mouse, etc.) into the middle Type-C port.
# Power the board from the UART or JTAG port for the duration of the test.
#
# Run as root:  sudo bash usb_check.sh
echo "== lsusb (the root hub should always show; your device only if the port works) =="
lsusb 2>&1
echo "== USB devices in sysfs =="
ls /sys/bus/usb/devices/ 2>&1
echo "== dmesg: usb / ulpi / phy / chipidea =="
dmesg | grep -i -E "usb|ulpi|phy|chipidea|ci_hdrc" | tail -25
echo "== block devices (a USB stick appears as sdX) =="
lsblk 2>&1 | grep -v -E "mmcblk|loop"
echo "== device tree: dr_mode and usb-phy of the controller =="
for p in /proc/device-tree/axi/usb@e0002000 /proc/device-tree/amba/usb@e0002000; do
  [ -d "$p" ] && { for f in dr_mode usb-phy phy_type; do [ -e "$p/$f" ] && echo "$f: $(tr -d '\0' < $p/$f | head -c 60)"; done; }
done
