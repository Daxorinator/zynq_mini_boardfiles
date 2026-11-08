#!/usr/bin/env python3
"""HDMI output test (run as root on the board, with a monitor on the HDMI connector):

    python3 hdmi_test.py [bars|ramp|checks|white|off]

Loads hdmi_test.bit and shows a 640x480@60 Hz pattern. Needs a monitor/TV; the board cannot detect the sink,
so success is what you see: bars should read white, yellow, cyan, green, magenta, red, blue, black.
Status: built but never run with a monitor.
"""
import os
import sys
from pynq import Overlay

PATTERNS = {"bars": 0, "ramp": 1, "checks": 2, "white": 3}
name = sys.argv[1] if len(sys.argv) > 1 else "bars"
here = os.path.dirname(os.path.abspath(__file__))
ol = Overlay(os.path.join(here, "hdmi_test.bit"))
ctrl = ol.ip_dict["ctrl"]
from pynq import MMIO
g = MMIO(ctrl["phys_addr"], 0x10000)
if name == "off":
    g.write(0x0, 0)
    print("HDMI 5 V output disabled")
elif name in PATTERNS:
    g.write(0x0, 1 | (PATTERNS[name] << 1))
    print(f"HDMI output enabled, pattern: {name}")
else:
    sys.exit(__doc__)
