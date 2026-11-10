# Peripheral testing scripts for Zynq Mini

These scripts check PS-side peripherals under PYNQ.
Copy them to the board (Jupyter's upload button, or `wget`/`scp`) and run as root unless stated.

| Script | Checks |
|---|---|
| `ps_gpio_test.py` | PS LED D6 (MIO9) and KEY1 (MIO0) through `pynq.GPIO` |
| `xadc_read.py` | XADC die temperature and supply voltages through Linux IIO |
| `sd1_test.sh` | Second TF slot (SD1): detection, read speed, write/read-back |
| `usb_check.sh` | USB host port: enumeration of a plugged-in device |
| `usb_gadget_msc.sh` | USB device mode: board appears as a 32 MiB USB drive on a PC |
| `usb_gadget_net.sh` | USB device mode: serial console (CDC ACM) plus USB Ethernet (NCM, ECM or RNDIS) with a fixed address |

## PS LED and KEY1

```
sudo -i
python3 ps_gpio_test.py
```

The LED blinks five times, then lights while KEY1 is held and prints `pressed`/`released`.
Active levels: LED high, key low. If `GPIO(...)` raises "busy", another driver owns the pin.
(`cat /sys/kernel/debug/gpio` lists the owners).

## XADC temperature and voltage

```
python3 xadc_read.py
```

A die temperature of roughly 40-70 C is normal.
If nothing shows up, check `zcat /proc/config.gz | grep -i xadc` and `dmesg | grep -i xadc`; the kernel driver or the device tree node may be missing.

## SD1

Put a card in the SD1 slot.

```
sudo bash sd1_test.sh
```

It lists `/dev/mmcblk*` (SD1 should be `mmcblk1`), reads 100 MB, mounts, writes and reads back one small file,
then unmounts and prints `SD1 OK`. It never formats or repartitions, so the card should be fat32 or ext4

## USB host

The USB port is the **middle Type-C connector** (USB3320 ULPI PHY, host and device capable).
To test the host side:

1. Power the board from the UART or JTAG port for the duration of the test.
2. Plug a USB device into the middle port through a Type-C to USB-A adapter (a flash drive or a keyboard is easiest).
3. Run `sudo bash usb_check.sh` after plugging it in.

It prints `lsusb`, USB-related `dmesg` lines, block devices and the controller's device tree properties.
Success looks like the device appearing in `lsusb`, and for a flash drive, `sdX` in `lsblk`.

## USB device mode - MSC

Run `sudo bash usb_gadget_msc.sh start` with the middle Type-C port connected to a PC by an ordinary cable.
The PC sees a blank 32 MiB drive; format it, copy a file, eject, then `sudo bash usb_gadget_msc.sh check`
mounts the backing image read-only on the board and lists it. `stop` unbinds and removes the gadget.

## USB device mode - NCM

Run `sudo bash usb_gadget_net.sh start ncm` with the middle Type-C port connected to a PC by an ordinary cable.
A Windows 11 PC should see a UsbNcm network device, which will need to be manually configured to `192.168.2.1/24`.
Once configured, the PYNQ Jupyter web page should be accessible at `192.168.2.99:9090` and the board should be pingable at the same IP.
SSH and other network-based features should also work without issue. `sudo bash usb_gadget_net.sh stop ncm` unbinds and removes the `usb0` interface taking NCM down.