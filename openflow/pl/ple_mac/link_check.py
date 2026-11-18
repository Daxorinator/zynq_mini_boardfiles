#!/usr/bin/env python3
"""Check the PL Ethernet link with the ple_mdio / ple_mac bitstream loaded (run on the board as root, PYNQ venv).
Prints the PHY id, restarts auto-negotiation offering 1000 Mb/s only, and polls until the link is up (or 15 s)."""
import mmap, os, sys, time
from pynq import Clocks
from mdio import Mdio
Clocks.fclk0_mhz = 100
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x40000000)
rd = lambda o: int.from_bytes(m[o:o + 4], "little")
wr = lambda o, v: m.__setitem__(slice(o, o + 4), (v & 0xFFFFFFFF).to_bytes(4, "little"))
md = Mdio(rd, wr); md.reset_phy()
print("PHY id %04x:%04x" % (md.read(0, 2), md.read(0, 3)))
md.advertise_gigabit_only()
t0 = time.time(); up = False
while time.time() - t0 < 15:
    bmsr = md.read(0, 1); bmsr = md.read(0, 1)             # link status bit latches low: read twice
    physr = md.read(0, 0x11)
    if bmsr & 4: up = True; break
    time.sleep(0.5)
speed = {0: "10", 1: "100", 2: "1000"}.get((physr >> 14) & 3, "?")
print("link %s  BMSR %#06x PHYSR %#06x speed %s Mb/s duplex %s (after %.1f s)" % ("UP" if up else "DOWN", bmsr, physr, speed, "full" if physr & 0x2000 else "half", time.time() - t0))
print("PL_LINK RESULT: %s" % ("UP" if up else "DOWN"))
