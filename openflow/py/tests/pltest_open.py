#!/usr/bin/env python3
"""PL self-test with the open-flow overlay zm_base (counterpart of pynq/overlay/pltest, no Vivado, no PYNQ). Run as root on the board:
    cd openflow/py && python3 tests/pltest_open.py ../pl/build/zm_base/zm_base.bin [test ...] [--header]
Tests: leds_keys clocks timer_irq dma eeprom oled ple_phy  (+ header with --header: it DRIVES the 34 header pins, unplug everything first).
The EEPROM test writes the last 8 bytes of the AT24C02 and restores them. The OLED test only writes to the display: look at the screen."""
import os, random, struct, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from zynqmini import load_bitstream, MMIO, set_fclk, fclk_mhz, allocate, UioIrq, Mdio

R = dict(ID=0x00, SCRATCH=0x04, LOCKED=0x08, LEDS=0x10, KEYS=0x14, HOUT0=0x20, HOUT1=0x24, HTRI0=0x28, HTRI1=0x2C, HIN0=0x30, HIN1=0x34,
         I2C=0x40, OLED=0x50, PHY=0x60, PHYPIN=0x64, TCTRL=0x70, TPERIOD=0x74, TCOUNT=0x78, TSTAT=0x7C, M50=0x80, M100=0x84, M150=0x88,
         M200=0x8C, MF1=0x90, MF2=0x94, WIN=0x98, SRC=0x108, DST=0x10C, LEN=0x110, CTRL=0x114, STATUS=0x118, CSUM=0x11C, CYC=0x120, BYTES=0x124)
regs = None
class Skip(Exception): pass
class Result:
    def __init__(self, status, text): self.status, self.text = status, text

def t_leds_keys():
    for pat in (1, 2, 4, 8, 0xF, 0):
        regs[R["LEDS"]] = pat
        if regs[R["LEDS"]] != pat: return Result("FAIL", "LED register readback %#x != %#x" % (regs[R["LEDS"]], pat))
        time.sleep(0.15)
    k = regs[R["KEYS"]] & 3
    if k != 3: return Result("WARN", "a key reads pressed (%#04b); release KEY2/KEY3 and rerun" % k)
    return Result("PASS", "LED registers ok (watch LED1..4 chase), KEY2/KEY3 idle high")

HDR_PIN = list(range(2, 19)) + list(range(39, 22, -1))      # bits 0..16 = right column pins 2..18, bits 17..33 = left column pins 39..23
def t_header():
    def drive(bit, val):
        t0, t1, o0, o1 = 0xFFFFFFFF, 3, 0, 0
        if bit < 32: t0 &= ~(1 << bit); o0 = val << bit
        else: t1 &= ~(1 << (bit - 32)); o1 = val << (bit - 32)
        regs[R["HOUT0"]] = o0; regs[R["HOUT1"]] = o1; regs[R["HTRI0"]] = t0; regs[R["HTRI1"]] = t1
        time.sleep(0.02)       # the inputs idle through weak pull-ups: a floating neighbour needs several ms to settle
        return regs[R["HIN0"]] | ((regs[R["HIN1"]] & 3) << 32)
    problems = []
    for b in range(34):
        hi, lo = drive(b, 1), drive(b, 0)
        if not (hi >> b) & 1: problems.append("pin %d cannot go high" % HDR_PIN[b])
        if (lo >> b) & 1: problems.append("pin %d cannot go low" % HDR_PIN[b])
        diff = (hi ^ lo) & ~(1 << b)
        problems += ["pin %d drags pin %d" % (HDR_PIN[b], HDR_PIN[j]) for j in range(34) if (diff >> j) & 1]
    regs[R["HTRI0"]] = 0xFFFFFFFF; regs[R["HTRI1"]] = 3
    return Result("FAIL", "; ".join(problems[:8])) if problems else Result("PASS", "all 34 header signals drive high and low, no coupling")

def meters():
    g = regs[R["WIN"]]
    for _ in range(2):                                          # let a full window finish after any clock change
        while regs[R["WIN"]] == g: time.sleep(0.005)
        g = regs[R["WIN"]]
    return [regs[R[n]] for n in ("M50", "M100", "M150", "M200", "MF1", "MF2")]
def t_clocks():
    if not regs[R["LOCKED"]] & 1: return Result("FAIL", "MMCM not locked")
    aclk = fclk_mhz(0) * 1e6; hz = lambda c: c * aclk / 2**20
    notes, bad = [], []
    c = meters()
    for i, want, label in ((0, 50, "PL osc"), (1, 100, "MMCM 100"), (2, 150, "MMCM 150"), (3, 200, "MMCM 200")):
        got = hz(c[i]) / 1e6; err = (got - want) / want * 100; notes.append("%s %.3f MHz (%+.3f %%)" % (label, got, err))
        if abs(err) > 0.1: bad.append(label)
    for n, idx, sweep in ((1, 4, (50, 100, 125, 200)), (2, 5, (75, 100, 150))):
        for want in sweep:
            actual = set_fclk(n, want); time.sleep(0.05)
            got = hz(meters()[idx]) / 1e6; err = (got - actual) / actual * 100
            notes.append("FCLK%d set %d -> %.3f, measured %.3f (%+.3f %%)" % (n, want, actual, got, err))
            if abs(err) > 0.5: bad.append("FCLK%d@%d" % (n, want))
    set_fclk(1, 50); set_fclk(2, 75)
    return Result("FAIL" if bad else "PASS", "; ".join(notes) + (" | out of tolerance: %s" % bad if bad else ""))

def t_timer_irq():
    try: irq = UioIrq("fabric")
    except FileNotFoundError: raise Skip("no 'fabric' UIO device (IRQ_F2P[0]) in the device tree")
    period, n = int(fclk_mhz(0) * 1e6 / 100), 100                # 10 ms
    regs[R["TCTRL"]] = 0; regs[R["TPERIOD"]] = period; regs[R["TSTAT"]] = 1
    t0 = time.time(); regs[R["TCTRL"]] = 3; got = 0
    for _ in range(n):
        irq.rearm()
        if irq.wait(1.0) is None: break
        regs[R["TSTAT"]] = 1; got += 1
    el = time.time() - t0; regs[R["TCTRL"]] = 0; irq.close()
    if got != n: return Result("FAIL", "only %d/%d timer interrupts arrived" % (got, n))
    err = (el - n * 0.01) / (n * 0.01) * 100
    return Result("PASS" if abs(err) < 3 else "WARN", "%d interrupts in %.4f s (expected %.2f s, %+.2f %%)" % (n, el, n * 0.01, err))

def t_dma():
    rnd = random.Random(3); notes = []
    def run(src, dst, n, mode, timeout=3.0):
        regs[R["CTRL"]] = 4; regs[R["SRC"]] = src; regs[R["DST"]] = dst; regs[R["LEN"]] = n; regs[R["CTRL"]] = 1 | (mode << 1)
        t0 = time.time()
        while not regs[R["STATUS"]] & 2:
            if time.time() - t0 > timeout: return None
        return regs[R["STATUS"]]
    for n in (128, 4096, 1 << 20):
        a, b = allocate(n), allocate(n + 256); d = rnd.randbytes(n); a.mm[:n] = d; b.mm[:n + 256] = b"\xa5" * (n + 256)
        st = run(a.phys_addr, b.phys_addr, n, 0)
        if st is None: return Result("FAIL", "copy %d bytes timed out" % n)
        want = sum(struct.unpack("<%dI" % (n // 4), d)) & 0xFFFFFFFF
        if st & 4 or bytes(b.mm[:n]) != d or bytes(b.mm[n:n + 256]) != b"\xa5" * 256 or regs[R["CSUM"]] != want:
            return Result("FAIL", "copy %d bytes: data/guard/checksum mismatch (status %#x)" % (n, st))
        notes.append("%d B in %d cycles" % (n, regs[R["CYC"]])); a.close(); b.close()
    a, b = allocate(4096), allocate(4096)                   # misaligned or odd-length runs must be rejected (error flag, nothing written)
    b.mm[:4096] = b"\x5a" * 4096
    for sa, da, n in ((a.phys_addr + 64, b.phys_addr, 256), (a.phys_addr, b.phys_addr + 32, 256), (a.phys_addr, b.phys_addr, 100)):
        st = run(sa, da, n, 0)
        if st is None or not st & 4 or bytes(b.mm[:4096]) != b"\x5a" * 4096: return Result("FAIL", "misaligned/odd-length DMA run not rejected (status %s)" % st)
    a.close(); b.close(); notes.append("misaligned runs rejected")
    irq = UioIrq(); a, b = allocate(1 << 20), allocate(1 << 20); d = rnd.randbytes(1 << 20); a.mm[:] = d; b.mm[:] = bytes(1 << 20)
    regs[R["CTRL"]] = 4; irq.rearm(); regs[R["SRC"]] = a.phys_addr; regs[R["DST"]] = b.phys_addr; regs[R["LEN"]] = 1 << 20; regs[R["CTRL"]] = 1 | 8
    got = irq.wait(3.0); regs[R["CTRL"]] = 4; irq.close()
    if got is None or bytes(b.mm[:]) != d: return Result("FAIL", "interrupt/data check failed")
    return Result("PASS", "copy loopback through HP0 intact (%s), done interrupt delivered" % "; ".join(notes))

class I2C:
    def __init__(self): self._set(1, 1)
    def _set(self, scl, sda): regs[R["I2C"]] = scl | (sda << 1); time.sleep(0.00002)
    def sda(self): return (regs[R["I2C"]] >> 1) & 1
    def start(self): self._set(1, 1); self._set(1, 0); self._set(0, 0)
    def stop(self): self._set(0, 0); self._set(1, 0); self._set(1, 1)
    def wbyte(self, b):
        for i in range(7, -1, -1): bit = (b >> i) & 1; self._set(0, bit); self._set(1, bit); self._set(0, bit)
        self._set(0, 1); self._set(1, 1); ack = self.sda() == 0; self._set(0, 1); return ack
    def rbyte(self, ack):
        v = 0; self._set(0, 1)
        for _ in range(8): self._set(1, 1); v = (v << 1) | self.sda(); self._set(0, 1)
        n = 0 if ack else 1; self._set(0, n); self._set(1, n); self._set(0, n); self._set(0, 1); return v
    def probe(self, a): self.start(); ok = self.wbyte(a << 1); self.stop(); return ok
    def read(self, a, off, n):
        self.start(); assert self.wbyte(a << 1) and self.wbyte(off); self.start(); assert self.wbyte((a << 1) | 1)
        d = [self.rbyte(i < n - 1) for i in range(n)]; self.stop(); return d
    def write(self, a, off, data):
        self.start(); assert self.wbyte(a << 1) and self.wbyte(off)
        for b in data: assert self.wbyte(b)
        self.stop(); time.sleep(0.02)
def t_eeprom():
    bus = I2C(); time.sleep(0.01)
    if bus.sda() != 1: return Result("FAIL", "SDA stuck low")
    found = [a for a in range(0x08, 0x78) if bus.probe(a)]
    if 0x50 not in found: return Result("FAIL", "devices %s; expected the AT24C02 at 0x50" % [hex(a) for a in found])
    saved = bus.read(0x50, 0xF8, 8); pat = [0xA5, 0x5A, 0x3C, 0xC3, 0x01, 0xFE, 0x80, 0x7F]
    try: bus.write(0x50, 0xF8, pat); got = bus.read(0x50, 0xF8, 8)
    finally: bus.write(0x50, 0xF8, saved)
    if got != pat: return Result("FAIL", "write/readback mismatch %s" % got)
    if bus.read(0x50, 0xF8, 8) != saved: return Result("FAIL", "could NOT restore the original bytes")
    return Result("PASS", "AT24C02 at 0x50 found, 8-byte write/readback ok, original bytes restored")

FONT = {"Z": [0x61, 0x51, 0x49, 0x45, 0x43], "Y": [0x07, 0x08, 0x70, 0x08, 0x07], "N": [0x7F, 0x04, 0x08, 0x10, 0x7F], "Q": [0x3E, 0x41, 0x51, 0x21, 0x5E],
        "M": [0x7F, 0x02, 0x0C, 0x02, 0x7F], "I": [0x00, 0x41, 0x7F, 0x41, 0x00], "P": [0x7F, 0x09, 0x09, 0x09, 0x06], "L": [0x7F, 0x40, 0x40, 0x40, 0x40],
        "O": [0x3E, 0x41, 0x41, 0x41, 0x3E], "K": [0x7F, 0x08, 0x14, 0x22, 0x41], " ": [0, 0, 0, 0, 0]}
def t_oled():
    SCLK, MOSI, DC, RES = 1, 2, 4, 8; st = {"v": 0}
    def o(v): st["v"] = v; regs[R["OLED"]] = v
    def byte(b, dc):
        base = (st["v"] & RES) | (DC if dc else 0)
        for i in range(7, -1, -1):
            bit = MOSI if (b >> i) & 1 else 0; o(base | bit); o(base | bit | SCLK)
        o(base)
    o(0); time.sleep(0.35); o(RES); time.sleep(0.35)      # long reset and settling like the proven hardware design (10 ms was not enough)
    for b in (0xAE, 0xD5, 0x80, 0xA8, 0x3F, 0xD3, 0x00, 0x40, 0x8D, 0x14, 0x20, 0x00, 0xA1, 0xC8, 0xDA, 0x12, 0x81, 0xCF, 0xD9, 0xF1, 0xDB, 0x40, 0xA4, 0xA6, 0xAF): byte(b, 0)
    fb = bytearray(1024)
    def px(x, y):
        if 0 <= x < 128 and 0 <= y < 64: fb[(y // 8) * 128 + x] |= 1 << (y % 8)
    for x in range(128): px(x, 0), px(x, 63)
    for y in range(64): px(0, y), px(127, y)
    for i in range(64): px(i * 2, i), px(127 - i * 2, i)
    cx = 30
    for ch in "ZYNQ MINI PL OK":
        for col, bits in enumerate(FONT.get(ch, FONT[" "])):
            for r in range(7):
                if (bits >> r) & 1: px(cx + col, 28 + r)
        cx += 6
    for b in (0x21, 0, 127, 0x22, 0, 7): byte(b, 0)
    for b in fb: byte(b, 1)
    return Result("MANUAL", "pattern sent: border, two diagonals and the text 'ZYNQ MINI PL OK'; look at the OLED")

def t_ple_phy():
    md = Mdio(lambda o: regs[o], lambda o, v: regs.write(o, v), R["PHY"], R["PHYPIN"]); md.reset_phy()
    for phy in range(32):
        r2 = md.read(phy, 2)
        if r2 not in (0, 0xFFFF): break
    else: return Result("FAIL", "no PHY answered on MDIO")
    r3 = md.read(phy, 3); r1 = md.read(phy, 1); r1 = md.read(phy, 1)
    ok = r2 == 0x001C and (r3 >> 4) == 0xC91
    return Result("PASS" if ok else "FAIL", "PHY at address %d, ID %#06x:%#06x (%s); status %#06x %s" % (phy, r2, r3, "Realtek RTL8211E" if ok else "unexpected", r1, "link up" if r1 & 4 else "no link"))

TESTS = [("leds_keys", t_leds_keys), ("clocks", t_clocks), ("timer_irq", t_timer_irq), ("dma", t_dma), ("eeprom", t_eeprom), ("oled", t_oled), ("ple_phy", t_ple_phy)]
if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]; bit = args.pop(0)
    want = args or [n for n, _ in TESTS] + (["header"] if "--header" in sys.argv else [])
    print("fpga:", load_bitstream(bit)); set_fclk(0, 100); regs = MMIO(0x40000000, 0x1000)
    assert regs[R["ID"]] == 0x5A4D4231, "wrong design loaded (ID %#x)" % regs[R["ID"]]
    table = dict(TESTS); table["header"] = t_header; counts = {}
    for name in want:
        try: r = table[name]()
        except Skip as e: r = Result("SKIP", str(e))
        except Exception as e: r = Result("FAIL", "%s: %s" % (type(e).__name__, e))
        counts[r.status] = counts.get(r.status, 0) + 1; print("%-10s %-6s %s" % (name, r.status, r.text))
    if "header" not in want: print("header     SKIP   not run (it drives the header pins; unplug everything and pass --header)")
    print("PLTEST_OPEN SUMMARY:", counts); sys.exit(1 if counts.get("FAIL") else 0)
