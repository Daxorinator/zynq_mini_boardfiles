#!/bin/bash
# Runs inside the rootfs chroot (under QEMU) during the sdbuild package stage.
# Board-specific fixes for the ZYNQ MINI image.
set -e
set -x

# 1. This board is a DHCP *client* only. The prebuilt rootfs ships isc-dhcp-server, which has no
#    interface configured here and just fails at every boot. Disable it (and the IPv6 one).
for svc in isc-dhcp-server isc-dhcp-server6; do
    systemctl disable "$svc" || true            # sysv-install path; may complain inside a chroot
    rm -f "/etc/systemd/system/multi-user.target.wants/$svc.service"
    update-rc.d -f "$svc" remove || true
done

# 2. haveged is killed by its own systemd seccomp filter on armhf (SIGSYS, restart loop): the stock
#    unit allows no uname(), which armhf glibc calls at program startup. Allow just that call.
mkdir -p /etc/systemd/system/haveged.service.d
cat > /etc/systemd/system/haveged.service.d/armhf-uname.conf <<'CONF'
[Service]
# armhf glibc calls uname() at startup; the stock SystemCallFilter forbids it, so seccomp kills haveged.
SystemCallFilter=uname
CONF

# 3. Stable Ethernet MAC. The board has no programmed MAC, so U-Boot invents a random one at every boot
#    ("using random MAC address"). Derive a stable, locally administered MAC from the CID of the SD card
#    the system booted from: a reflashed card keeps its address (and DHCP lease), a different card gets a
#    different one. Applied before networking starts, while eth0 is still down.
install -d /usr/local/sbin
cat > /usr/local/sbin/zynqmini-mac <<'SCRIPT'
#!/bin/sh
# usage: zynqmini-mac [--print] [iface]     (default iface eth0)
PRINT=0; [ "$1" = "--print" ] && { PRINT=1; shift; }
IFACE=${1:-eth0}
root=$(sed -n 's|.*root=\(/dev/[^ ]*\).*|\1|p' /proc/cmdline)
disk=$(basename "${root:-mmcblk0p2}" | sed 's/p[0-9]*$//')
[ -r "/sys/block/$disk/device/cid" ] || disk=mmcblk0
cid=$(cat "/sys/block/$disk/device/cid" 2>/dev/null) || { echo "zynqmini-mac: no CID, leaving MAC alone" >&2; exit 0; }
h=$(printf 'zynqmini-%s:%s' "$IFACE" "$cid" | sha256sum | cut -c1-12)
b0=$((0x$(echo "$h" | cut -c1-2)))
b0=$(( (b0 & 0xFE) | 0x02 ))                      # unicast, locally administered
mac=$(printf '%02x' "$b0"; echo "$h" | cut -c3-12 | sed 's/../:&/g')
[ "$PRINT" = 1 ] && { echo "$mac  (from $disk CID $cid)"; exit 0; }
ip link set dev "$IFACE" address "$mac" && echo "zynqmini-mac: $IFACE = $mac (from $disk)"
SCRIPT
chmod 755 /usr/local/sbin/zynqmini-mac

cat > /etc/systemd/system/zynqmini-mac.service <<'UNIT'
[Unit]
Description=Set a stable Ethernet MAC derived from the boot SD card
DefaultDependencies=no
Wants=sys-subsystem-net-devices-eth0.device network-pre.target
After=sys-subsystem-net-devices-eth0.device
Before=network-pre.target networking.service ifup@eth0.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/zynqmini-mac eth0

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable zynqmini-mac.service || ln -sf /etc/systemd/system/zynqmini-mac.service \
    /etc/systemd/system/multi-user.target.wants/zynqmini-mac.service
[ -e /etc/systemd/system/multi-user.target.wants/zynqmini-mac.service ] || { echo "ERROR: zynqmini-mac not enabled" >&2; exit 1; }

# 4. No unattended upgrades. apt-daily-upgrade.service ran for ~90 s right after every boot (the timer is
#    persistent and fires as soon as the clock is set), starving a 512 MB board while Jupyter starts, and
#    upgrading packages behind the user's back is not wanted on this image. Manual apt still works.
for unit in apt-daily-upgrade.timer unattended-upgrades.service; do
    systemctl disable "$unit" || true
done
systemctl mask apt-daily-upgrade.service || ln -sf /dev/null /etc/systemd/system/apt-daily-upgrade.service
rm -f /etc/systemd/system/timers.target.wants/apt-daily-upgrade.timer \
      /etc/systemd/system/multi-user.target.wants/unattended-upgrades.service

# 5. USB role switching and the default USB gadget. The PS USB port (chipidea, ULPI PHY) uses a software role switch (usb-role-switch in
#    the device tree): hardware OTG sensing stalls the gadget link. Boot default is DEVICE with a gadget
#    (serial console + NCM Ethernet, board 192.168.2.99/24 (the PYNQ default), PC 192.168.2.1/24): device mode never drives VBUS, so a
#    PC cable is safe at boot. For a keyboard/flash drive run "zynqmini-usb-role host" (unplug the PC cable first,
#    host drives VBUS); "zynqmini-usb-role device" returns to the gadget.
cat > /usr/local/sbin/zynqmini-usb-role <<'SCRIPT'
#!/bin/sh
# usage: zynqmini-usb-role [host|device|none|status]
R=$(ls /sys/class/usb_role/*/role 2>/dev/null | head -1)
[ -n "$R" ] || { echo "zynqmini-usb-role: no role switch (kernel/device tree without usb-role-switch)" >&2; exit 1; }
G=/sys/kernel/config/usb_gadget
case "${1:-status}" in
status) cat "$R" ;;
host|none)
    # unbind any gadget first, a bound gadget would be left half-alive
    for u in "$G"/*/UDC; do [ -e "$u" ] && echo "" > "$u" 2>/dev/null; done
    echo "$1" > "$R"; cat "$R" ;;
device)
    # Writing "device" while already in the gadget role is ignored by the driver (VBUS is never evaluated),
    # so go through host. The device switch waits ~5 s ("timeout waiting for ... in OTGSC" is harmless).
    # Cable must be plugged into the PC and no host-side device attached.
    for u in "$G"/*/UDC; do [ -e "$u" ] && echo "" > "$u" 2>/dev/null; done
    if [ "$(cat "$R")" = none ]; then
        echo device > "$R"; sleep 6        # from "none" no detour is needed (no VBUS pulse towards the PC)
    fi
    if [ "$(cat "$R")" != device ] || [ -z "$(ls /sys/class/udc 2>/dev/null)" ]; then
        echo host > "$R"; sleep 1; echo device > "$R"; sleep 6
    fi
    UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
    # rebind existing gadgets so the PC re-enumerates them (a role change alone leaves the PC link dead)
    for d in "$G"/*/; do
        [ -e "${d}UDC" ] && [ -n "$UDC" ] && echo "$UDC" > "${d}UDC" 2>/dev/null
    done
    cat "$R" ;;
*) echo "usage: $0 [host|device|none|status]" >&2; exit 1 ;;
esac
SCRIPT
chmod 755 /usr/local/sbin/zynqmini-usb-role

cat > /usr/local/sbin/zynqmini-usb-gadget <<'SCRIPT'
#!/bin/sh
# usage: zynqmini-usb-gadget start|stop      serial (ttyGS0 getty) + NCM Ethernet, board = 192.168.2.99/24 (PYNQ default)
G=/sys/kernel/config/usb_gadget/zynqmini_net
case "$1" in
start)
    [ -d "$G" ] && exit 0
    zynqmini-usb-role device >/dev/null || exit 1
    for m in libcomposite usb_f_acm usb_f_ncm; do modprobe "$m" || exit 1; done
    mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
    UDC=$(ls /sys/class/udc | head -1); [ -n "$UDC" ] || exit 1
    mkdir -p "$G" && cd "$G" || exit 1
    echo 0x1d6b > idVendor; echo 0x0104 > idProduct; echo 0x0200 > bcdUSB
    echo 0xEF > bDeviceClass; echo 0x02 > bDeviceSubClass; echo 0x01 > bDeviceProtocol
    mkdir -p strings/0x409 configs/c.1/strings/0x409 functions/acm.usb0 functions/ncm.usb0
    echo ZYNQMININET01 > strings/0x409/serialnumber
    echo "Bochen Jingxin" > strings/0x409/manufacturer; echo "ZYNQ MINI" > strings/0x409/product
    echo "serial + ncm" > configs/c.1/strings/0x409/configuration
    echo 02:5a:59:4d:00:01 > functions/ncm.usb0/host_addr; echo 02:5a:59:4d:00:02 > functions/ncm.usb0/dev_addr
    ln -s functions/acm.usb0 configs/c.1/; ln -s functions/ncm.usb0 configs/c.1/
    echo "$UDC" > UDC || exit 1
    IF=$(cat functions/ncm.usb0/ifname)
    ip addr flush dev "$IF"; ip addr add 192.168.2.99/24 dev "$IF"; ip link set "$IF" up
    systemctl start serial-getty@ttyGS0.service ;;
stop)
    [ -d "$G" ] || exit 0
    systemctl stop serial-getty@ttyGS0.service
    echo "" > "$G/UDC"; rm -f "$G"/configs/c.1/acm.usb0 "$G"/configs/c.1/ncm.usb0
    rmdir "$G"/configs/c.1/strings/0x409 "$G"/configs/c.1 "$G"/functions/* "$G"/strings/0x409 "$G" ;;
*) echo "usage: $0 start|stop" >&2; exit 1 ;;
esac
SCRIPT
chmod 755 /usr/local/sbin/zynqmini-usb-gadget

cat > /etc/systemd/system/zynqmini-usb-gadget.service <<'UNIT'
[Unit]
Description=USB device mode: serial console + NCM Ethernet on the PS USB port
After=local-fs.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/zynqmini-usb-gadget start
ExecStop=/usr/local/sbin/zynqmini-usb-gadget stop
[Install]
WantedBy=multi-user.target
UNIT
systemctl enable zynqmini-usb-gadget.service || ln -sf /etc/systemd/system/zynqmini-usb-gadget.service \
    /etc/systemd/system/multi-user.target.wants/zynqmini-usb-gadget.service
[ -e /etc/systemd/system/multi-user.target.wants/zynqmini-usb-gadget.service ] || { echo "ERROR: zynqmini-usb-gadget not enabled" >&2; exit 1; }

# The PYNQ default address 192.168.2.99 lives on usb0 (gadget, above) in this image, so drop the stock eth0:1
# alias that would put the same address on the same subnet on eth0 (replies could leave on the wrong port).
# allow-hotplug (not auto): ifup@eth0 runs from udev as soon as eth0 exists instead of after "networking.service"
# (which waited for udev to settle), so the PHY link and DHCP start about 5 s earlier and the boot target no longer
# waits for the lease.
cat > /etc/network/interfaces.d/eth0 <<'IFACE'
allow-hotplug eth0
iface eth0 inet dhcp
IFACE
! grep -q '192.168.2.99' /etc/network/interfaces.d/eth0 || { echo "ERROR: eth0:1 alias still present" >&2; exit 1; }

# 6. Boot time (measured with systemd-analyze on the board).
#    - dhclient started ~4 s before the PHY link was up, so its first requests were lost and the 3 s / 8 s
#      retry backoff delayed the lease to ~34 s. Retry quickly instead.
grep -q '^initial-interval' /etc/dhcp/dhclient.conf || printf 'initial-interval 1;\nbackoff-cutoff 3;\n' >> /etc/dhcp/dhclient.conf
#    - Services with no use on this board compete with Jupyter for the two Cortex-A9 cores during boot:
#      crash reporting, e2scrub, networkd-dispatcher (ifupdown is used), console keyboard setup, Ubuntu
#      Pro/advantage, motd news, man-db rebuild, Bluetooth (no hardware).
for unit in apport-autoreport.path apport-forward.socket e2scrub_reap.service e2scrub_all.timer \
            networkd-dispatcher.service keyboard-setup.service ua-license-check.path ua-reboot-cmds.service \
            ua-timer.timer motd-news.timer man-db.timer bluetooth.service setvtrgb.service; do
    systemctl disable "$unit" || true
done
#    - Give Jupyter (the slowest start, ~30 s of CPU-bound Python) priority over the other boot-time work.
mkdir -p /etc/systemd/system/jupyter.service.d
printf '[Service]\nNice=-5\n' > /etc/systemd/system/jupyter.service.d/priority.conf

# 7. PYNQ assumes a 50 MHz PS clock on Zynq-7000 (PYNQ-Z1/Z2). This board's PS_CLK is 33.3333 MHz, so pynq.ps.Clocks
#    (and the FCLK settings Overlay.download() applies from the .hwh) came out 1.5x too high: IO PLL computed as 1500 MHz
#    instead of 1000 MHz, and a requested 100 MHz FCLK0 really ran at 66.7 MHz. Correct the default reference clock.
PS_PY=$(ls /usr/local/share/pynq-venv/lib/python3*/site-packages/pynq/ps.py 2>/dev/null | head -1)
[ -n "$PS_PY" ] || { echo "ERROR: pynq/ps.py not found" >&2; exit 1; }
sed -i '/^class _ClocksZynq/,/^class Clocks/ s/DEFAULT_SRC_CLK_MHZ = 50\.0/DEFAULT_SRC_CLK_MHZ = 33.333/' "$PS_PY"
python3 - "$PS_PY" <<'PY' || exit 1
import re, sys
t = open(sys.argv[1]).read()
z = t[t.index("class _ClocksZynq"):t.index("class Clocks(")]
assert "DEFAULT_SRC_CLK_MHZ = 33.333" in z, "ps.py patch did not apply"
PY

# Fail the build loudly if the DHCP servers are still enabled.
for svc in isc-dhcp-server isc-dhcp-server6; do
    if [ -e "/etc/systemd/system/multi-user.target.wants/$svc.service" ]; then
        echo "ERROR: $svc is still enabled" >&2; exit 1
    fi
done

for f in /etc/systemd/system/timers.target.wants/apt-daily-upgrade.timer \
         /etc/systemd/system/multi-user.target.wants/unattended-upgrades.service; do
    [ ! -e "$f" ] || { echo "ERROR: $f is still enabled" >&2; exit 1; }
done
[ "$(readlink /etc/systemd/system/apt-daily-upgrade.service)" = /dev/null ] || { echo "ERROR: apt-daily-upgrade.service not masked" >&2; exit 1; }
