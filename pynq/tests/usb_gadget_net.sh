#!/bin/bash
# USB device-mode test: serial console (CDC ACM) + USB Ethernet on the Type-C port, to a PC.
#
#   sudo bash usb_gadget_net.sh start [ncm|ecm|rndis]   build the gadget and bind it (default: ncm)
#   sudo bash usb_gadget_net.sh status                   UDC state, usb0 address, getty state
#   sudo bash usb_gadget_net.sh stop                     unbind and remove the gadget
#
# Ethernet function by host OS:  ncm = Linux, macOS, Windows 11    ecm = Linux, macOS
#                                rndis = Windows 10 and later (adds the MS OS descriptor so it needs no driver)
#
# The image already starts a serial+NCM gadget at boot (zynqmini-usb-gadget.service, 192.168.2.99); run "systemctl stop
# zynqmini-usb-gadget" before using this script for ecm/rndis. On the image's role-switch kernel the script runs "zynqmini-usb-role device" itself; undo with
#   zynqmini-usb-role host   (unplug the PC cable first: host mode drives VBUS).
#
# Wiring: power the board from the UART or JTAG port, take any USB host adapter / drive out of the Type-C port,
# connect that port to the PC with an ordinary cable, then run "start". The port switches to device mode by
# itself.
#
# Addresses (no DHCP server runs on the board, so the PC needs a fixed address):
#     board usb0 = 192.168.2.99/24         PC = 192.168.2.1/24   (set it by hand on the PC)
#   then:  ssh xilinx@192.168.2.99     Jupyter: http://192.168.2.99:9090
# Serial: a login prompt appears on the PC as /dev/ttyACM0 (Linux), /dev/cu.usbmodem* (macOS) or a COM port
# (Windows), 115200 8N1 (the speed is ignored by CDC ACM).
set -u
G=/sys/kernel/config/usb_gadget/zynqmini_net
BOARD_IP=${BOARD_IP:-192.168.2.99/24}
FUNC=${2:-ncm}

case "${1:-}" in
start)
  case "$FUNC" in ncm|ecm|rndis) ;; *) echo "function must be ncm, ecm or rndis"; exit 1 ;; esac
  [ -d "$G" ] && { echo "gadget already exists, run stop first"; exit 1; }
  for m in libcomposite usb_f_acm usb_f_$FUNC; do
    modprobe "$m" || { echo "cannot load $m (kernel gadget option missing?)"; exit 1; }
  done
  # Image with usb-role-switch: go to device mode first (needs the PC cable in, no host-side device attached).
  command -v zynqmini-usb-role >/dev/null && [ "$(zynqmini-usb-role status 2>/dev/null)" != device ] && zynqmini-usb-role device
  UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
  [ -n "$UDC" ] || { echo "no UDC: the port is in host mode. Remove the host adapter/drive and connect the cable to the PC first."; exit 1; }
  mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
  mkdir -p "$G" && cd "$G" || exit 1
  echo 0x1d6b > idVendor; echo 0x0104 > idProduct          # Linux Foundation, composite gadget
  echo 0x0200 > bcdUSB
  echo 0xEF > bDeviceClass; echo 0x02 > bDeviceSubClass; echo 0x01 > bDeviceProtocol   # composite with IAD
  mkdir -p strings/0x409 configs/c.1/strings/0x409
  echo ZYNQMININET01 > strings/0x409/serialnumber
  echo "Bochen Jingxin" > strings/0x409/manufacturer
  echo "ZYNQ MINI" > strings/0x409/product
  echo "serial + $FUNC" > configs/c.1/strings/0x409/configuration
  mkdir -p functions/acm.usb0 "functions/$FUNC.usb0"
  # Fixed MACs so the PC does not see a new network adapter each time (locally administered, unicast).
  echo 02:5a:59:4d:00:01 > "functions/$FUNC.usb0/host_addr"
  echo 02:5a:59:4d:00:02 > "functions/$FUNC.usb0/dev_addr"
  if [ "$FUNC" = rndis ]; then            # make Windows pick the built-in RNDIS driver
    echo 1 > os_desc/use; echo 0xcd > os_desc/b_vendor_code; echo MSFT100 > os_desc/qw_sign
    echo RNDIS > "functions/rndis.usb0/os_desc/interface.rndis/compatible_id"
    echo 5162001 > "functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id"
  fi
  ln -s functions/acm.usb0 configs/c.1/
  ln -s "functions/$FUNC.usb0" configs/c.1/
  [ "$FUNC" = rndis ] && ln -s configs/c.1 os_desc/
  echo "$UDC" > UDC || { echo "bind failed (see dmesg)"; exit 1; }
  # The network interface exists once the function is created; give it its address and bring it up.
  IF=$(cat "functions/$FUNC.usb0/ifname")
  ip addr flush dev "$IF" 2>/dev/null
  ip addr add "$BOARD_IP" dev "$IF" && ip link set "$IF" up
  systemctl start serial-getty@ttyGS0.service 2>&1 | head -2
  echo "gadget bound to $UDC: serial (ttyGS0) + $FUNC as $IF = $BOARD_IP"
  echo "PC side: give the new network adapter 192.168.2.1/24, then ssh xilinx@${BOARD_IP%/*}"
  ;;
status)
  for u in /sys/class/udc/*; do [ -e "$u" ] && echo "$(basename "$u"): $(cat "$u/state")"; done
  [ -e $G/UDC ] && echo "bound to: $(cat $G/UDC)" || echo "no gadget"
  ip -br addr show 2>/dev/null | grep -E '^usb[0-9]' || echo "no usb network interface"
  echo "getty: $(systemctl is-active serial-getty@ttyGS0.service 2>&1)"
  dmesg | grep -i -E "udc|gadget|configfs|ci_hdrc|usb0|rndis|ncm|ecm|cdc_acm" | tail -8
  ;;
stop)
  [ -d $G ] || { echo "no gadget"; exit 0; }
  systemctl stop serial-getty@ttyGS0.service 2>/dev/null
  echo "" > $G/UDC 2>/dev/null
  rm -f $G/os_desc/c.1
  find $G/configs/c.1 -maxdepth 1 -type l -exec rm -f {} +
  rmdir $G/configs/c.1/strings/0x409 $G/configs/c.1 2>&1
  rmdir $G/functions/* 2>&1
  rmdir $G/strings/0x409 $G 2>&1
  echo stopped
  ;;
*) sed -n '2,22p' "$0"; exit 1 ;;
esac
