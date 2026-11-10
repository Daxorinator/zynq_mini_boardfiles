#!/bin/bash
# USB device-mode test: make the ZYNQ MINI appear as a USB flash drive on a PC.
#
#   sudo bash usb_gadget_msc.sh start   create a 32 MiB backing file and expose it (configfs mass storage)
#   sudo bash usb_gadget_msc.sh status  UDC state and what the PC has done so far
#   sudo bash usb_gadget_msc.sh check   after "Eject" on the PC: mount the backing file read-only and list it
#   sudo bash usb_gadget_msc.sh stop    unbind and remove the gadget
#
# Wiring: power the board from the UART or JTAG port, take any USB host adapter / drive out of the middle
# Type-C port, and connect that port to the PC with an ordinary Type-C cable.
#
# The PC will offer to format the blank disk the first time.
# When formatted, write any file under 32 MiB to the device to complete the test.
set -u
G=/sys/kernel/config/usb_gadget/zynqmini
IMG=${GADGET_IMG:-/tmp/gadget.img}
MNT=/mnt/gadget_chk

case "${1:-}" in
start)
  modprobe libcomposite && modprobe usb_f_mass_storage || { echo "gadget modules missing"; exit 1; }
  UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
  [ -n "$UDC" ] || { echo "no UDC: the port is in host mode. Remove the host adapter/drive and connect the cable to the PC first."; exit 1; }
  [ -f "$IMG" ] || dd if=/dev/zero of="$IMG" bs=1M count=32 status=none
  mkdir -p $G && cd $G || exit 1
  echo 0x1d6b > idVendor; echo 0x0104 > idProduct      # Linux Foundation, composite gadget
  mkdir -p strings/0x409 configs/c.1/strings/0x409 functions/mass_storage.0
  echo ZYNQMINI0001 > strings/0x409/serialnumber
  echo "Bochen Jingxin" > strings/0x409/manufacturer
  echo "ZYNQ MINI" > strings/0x409/product
  echo "mass storage" > configs/c.1/strings/0x409/configuration
  echo 0 > functions/mass_storage.0/lun.0/ro          # must come before "file": ro cannot change once attached
  echo 1 > functions/mass_storage.0/lun.0/removable
  echo "$IMG" > functions/mass_storage.0/lun.0/file
  ln -sf functions/mass_storage.0 configs/c.1/ 2>/dev/null
  echo "$UDC" > UDC && echo "gadget bound to $UDC, backing file $IMG"
  ;;
status)
  for u in /sys/class/udc/*; do echo "$(basename $u): $(cat $u/state)"; done
  [ -e $G/UDC ] && echo "bound to: $(cat $G/UDC)"
  dmesg | grep -i -E "udc|gadget|g_mass|configfs|ci_hdrc" | tail -8
  ;;
check)
  mkdir -p $MNT
  mount -o ro,loop "$IMG" $MNT 2>&1 || { echo "could not mount $IMG (not formatted by the PC yet?)"; rmdir $MNT; exit 1; }
  ls -la $MNT; umount $MNT; rmdir $MNT
  ;;
stop)
  [ -d $G ] || { echo "no gadget"; exit 0; }
  echo "" > $G/UDC 2>/dev/null
  rm -f $G/configs/c.1/mass_storage.0
  rmdir $G/configs/c.1/strings/0x409 $G/configs/c.1 $G/functions/mass_storage.0 $G/strings/0x409 $G 2>&1
  echo stopped
  ;;
*) sed -n '2,12p' "$0"; exit 1 ;;
esac
