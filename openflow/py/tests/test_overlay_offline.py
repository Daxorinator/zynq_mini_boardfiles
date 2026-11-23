#!/usr/bin/env python3
"""Offline test of zynqmini.Overlay / Register / HpDma against a fake register file (no board needed): python3 tests/test_overlay_offline.py"""
import os, sys, tempfile, json
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from zynqmini.overlay import Overlay, MAPS
from zynqmini.hp_dma import HpDma, DmaError

class FakeMmio:
    """Register file with the hp_dma behaviour: CTRL bit0 start completes at once (error if misaligned/odd length), CTRL bit2 clears."""
    def __init__(self): self.r = {}; self.log = []
    def read(self, off):
        self.log.append(("r", off)); return self.r.get(off, 0)
    def write(self, off, v):
        self.log.append(("w", off, v)); self.r[off] = v & 0xFFFFFFFF
        if off == 0x14 or off == 0x114:
            st = off + 4
            if v & 4: self.r[st] = 0
            if v & 1:
                src, dst, ln = self.r.get(off - 0x0C, 0), self.r.get(off - 0x08, 0), self.r.get(off - 0x04, 0)
                bad = src % 128 or ln % 128 or (not v & 2 and dst % 128)
                self.r[st] = 2 | (4 if bad else 0)
                self.r[off + 8] = 0xABCD1234                         # CHECKSUM register

fails = 0
def check(name, cond):
    global fails
    print("%-4s %s" % ("ok" if cond else "FAIL", name)); fails += (not cond)

tmp = tempfile.mkdtemp(); open(os.path.join(tmp, "x.bin"), "wb").write(b"\0")
for name in ("zm_base", "hp_dma", "ple_mac"):
    mp = os.path.join(MAPS, name + ".json"); meta = json.load(open(mp))
    ol = Overlay(os.path.join(tmp, "x.bin"), map=mp, download=False, mmio=FakeMmio())
    check("%s: map loads, %d registers" % (name, len(ol.registers)), len(ol.registers) >= 10 and ol.name == name)
    offs = [r.offset for r in ol.registers.values()]
    check("%s: register offsets unique and word aligned" % name, len(set(offs)) == len(offs) and all(o % 4 == 0 for o in offs))
ol = Overlay(os.path.join(tmp, "x.bin"), map=os.path.join(MAPS, "zm_base.json"), download=False, mmio=FakeMmio())
ol.LEDS = 5; check("attribute write reaches the register offset", ol.mmio.r[0x10] == 5 and ol.LEDS == 5)
try: ol.KEYS = 1; ro = False
except PermissionError: ro = True
check("read-only register refuses writes", ro)
try: ol.DMA_CTRL; wo = False
except PermissionError: wo = True
check("write-only register refuses reads", wo)
check("unknown attribute raises", not hasattr(ol, "NOPE"))
check("repr lists registers", "LEDS" in repr(ol) and "DMA_STATUS" in repr(ol))
pl = Overlay(os.path.join(tmp, "x.bin"), map=os.path.join(MAPS, "ple_mac.json"), download=False, mmio=FakeMmio())
pl.TXBUF[3] = 0x11223344; check("array write", pl.mmio.r[0x200 + 12] == 0x11223344 and len(pl.TXBUF) == 80)
try: pl.RXBUF[0] = 1; arr = False
except PermissionError: arr = True
check("read-only array refuses writes", arr)
class Buf:                                                    # stands in for a contiguous buffer
    def __init__(self, phys, size): self.phys_addr, self.size = phys, size
for name, pre in (("hp_dma", ""), ("zm_base", "DMA_")):
    o = Overlay(os.path.join(tmp, "x.bin"), map=os.path.join(MAPS, name + ".json"), download=False, mmio=FakeMmio()); d = HpDma(o)
    check("%s: copy of aligned buffers completes" % name, d.copy(Buf(0x1000000, 4096), Buf(0x2000000, 4096)) == 4096)
    check("%s: checksum returns the checksum register" % name, d.checksum(Buf(0x1000000, 4096)) == 0xABCD1234)
    try: d.copy(Buf(0x1000040, 4096), Buf(0x2000000, 4096)); rej = False
    except DmaError: rej = True
    check("%s: misaligned source is reported" % name, rej)
print("overlay offline test:", "PASS" if not fails else "%d FAILED" % fails); sys.exit(1 if fails else 0)
