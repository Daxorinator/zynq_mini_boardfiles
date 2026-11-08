#!/usr/bin/env python3
"""Read the Zynq XADC (die temperature and supply voltages) through the Linux IIO interface.
Run on the board (root not required):  python3 xadc_read.py   UNTESTED on hardware.
Needs the xilinx-xadc driver (CONFIG_XILINX_XADC) and an XADC node in the device tree.
"""
import glob, os

def rd(path):
    with open(path) as f:
        return f.read().strip()

devs = [d for d in glob.glob("/sys/bus/iio/devices/iio:device*")
        if "xadc" in rd(d + "/name").lower()]
if not devs:
    raise SystemExit("No XADC IIO device found. Check: ls /sys/bus/iio/devices/ ; "
                     "zcat /proc/config.gz | grep -i xadc ; dmesg | grep -i xadc")
d = devs[0]
print("Device:", d, "(", rd(d + "/name"), ")")

def value(chan):
    """IIO convention: value = (raw + offset) * scale  (millidegrees C or millivolts)."""
    raw = float(rd(f"{d}/in_{chan}_raw"))
    off = float(rd(f"{d}/in_{chan}_offset")) if os.path.exists(f"{d}/in_{chan}_offset") else 0.0
    if os.path.exists(f"{d}/in_{chan}_scale"):
        scale = float(rd(f"{d}/in_{chan}_scale"))
    else:
        scale = float(rd(f"{d}/in_voltage_scale"))
    return (raw + off) * scale

print(f"Die temperature: {value('temp0') / 1000:.1f} C")
for name in sorted(os.path.basename(p)[3:-4] for p in glob.glob(d + "/in_voltage*_raw")):
    print(f"{name:20s} {value(name) / 1000:.3f} V")
