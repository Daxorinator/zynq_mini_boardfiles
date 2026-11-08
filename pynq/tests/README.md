# Peripheral checks for the board

Scripts to run **on the ZYNQ MINI** to check PS-side peripherals under PYNQ. Status: `xadc_read.py` and the PS LED / KEY1
GPIO checks are verified on hardware (XADC read 52 C with sane rails; LED pin toggled and KEY1 idled high). `sd1_test.sh`
was covered by hand (SD1 hot-plug verified in the rebuilt image). `usb_check.sh` shows the USB controller probing and a
full-speed keyboard and a high-speed flash drive enumerating (one other drive failed; see `../BUILDING.md`). `usb_gadget_msc.sh` was run against a Windows PC: it
enumerated, the PC formatted and wrote a file, and the board read it back.
Copy them to the board (Jupyter's upload button, or `wget`/`scp`) and run as root unless stated.

| Script | Checks |
|---|---|
| `ps_gpio_test.py` | PS LED D6 (MIO9) and KEY1 (MIO0) through `pynq.GPIO` |
| `xadc_read.py` | XADC die temperature and supply voltages through Linux IIO |
| `sd1_test.sh` | Second TF slot (SD1): detection, read speed, write/read-back |
| `usb_check.sh` | USB host port: enumeration of a plugged-in device |
| `usb_gadget_msc.sh` | USB device mode: board appears as a 32 MiB USB drive on a PC (`start`, `status`, `check`, `stop`) |
| `usb_gadget_net.sh` | USB device mode: serial console (CDC ACM) plus USB Ethernet (NCM, ECM or RNDIS) with a fixed address (`start [ncm\|ecm\|rndis]`, `status`, `stop`). Verified with NCM against Windows 11 (serial and Jupyter over USB). Needs the role-switch image: it runs `zynqmini-usb-role device` itself |

## PS LED and KEY1

```
sudo -i
python3 ps_gpio_test.py
```

The LED blinks five times, then lights while KEY1 is held and prints `pressed`/`released`.
Active levels: LED high, key low. If `GPIO(...)` raises "busy", another driver owns the pin
(`cat /sys/kernel/debug/gpio` lists the owners).

## XADC temperature and voltage

```
python3 xadc_read.py
```

Or by hand:

```
ls /sys/bus/iio/devices/                  # look for a device whose name contains xadc
cat /sys/bus/iio/devices/iio:device0/name
d=/sys/bus/iio/devices/iio:device0
python3 -c "r=float(open('$d/in_temp0_raw').read()); o=float(open('$d/in_temp0_offset').read()); s=float(open('$d/in_temp0_scale').read()); print((r+o)*s/1000,'C')"
cat $d/in_voltage0_vccint_raw $d/in_voltage_scale     # volts = raw * scale / 1000
```

Channel names (`vccint`, `vccaux`, `vccbram`, ...) vary by device; list them with
`ls $d | grep in_voltage`. A die temperature of roughly 40-70 C is normal. If nothing shows up, check
`zcat /proc/config.gz | grep -i xadc` and `dmesg | grep -i xadc`; the kernel driver or the device tree node may be missing.

## SD1

Put a card in the **SD1/TF2** slot first (SD0 holds the boot card).

```
sudo bash sd1_test.sh
```

It lists `/dev/mmcblk*` (SD1 should be `mmcblk1`), reads 100 MB, mounts, writes and reads back one small file,
then unmounts and prints `SD1 OK`. It never formats or repartitions.

## USB host

The USB port is the **middle Type-C connector** (USB3320 ULPI PHY, host and device capable). To test the host side:

1. Power the board from the UART or JTAG port, not the USB port.
2. Plug a USB device into the middle port through a Type-C to USB-A adapter (a flash drive or a keyboard is easiest).
3. Run `sudo bash usb_check.sh` after plugging it in.

It prints `lsusb`, USB-related `dmesg` lines, block devices and the controller's device tree properties.
Success looks like the device appearing in `lsusb`, and a flash drive as `sdX` in `lsblk`.
If nothing enumerates, check `dmesg` for `device not accepting address` / `error -71`: those mean the device was seen but
the link failed, and trying a different device (a keyboard enumerates at full speed) tells you whether it is the device
or the port. A missing `ci_hdrc` / EHCI line means the device tree fix is not in your image. Send the script output.

## USB device mode

Run `sudo bash usb_gadget_msc.sh start` with the middle Type-C port connected to a PC by an ordinary cable (no host adapter or
drive in it, board powered from the UART or JTAG port). The PC sees a blank 32 MiB drive; format it, copy a file, eject, then
`sudo bash usb_gadget_msc.sh check` mounts the backing image read-only on the board and lists it. `stop` unbinds and removes
the gadget. The kernel only has the mass-storage function; serial/Ethernet gadgets are not built.
