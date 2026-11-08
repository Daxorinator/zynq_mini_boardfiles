#!/usr/bin/env python3
"""PL self-test for the ZYNQ MINI. Needs no cable and no add-on board.

Run as root on the board, from the folder holding pltest.bit / pltest.hwh / pltest.dtbo:

    python3 pltest_run.py                 # every test
    python3 pltest_run.py clocks dma      # selected tests
    python3 pltest_run.py --list

Tests: leds_keys  header  clocks  timer_irq  dma  eeprom  oled  ple_phy

UNPLUG ANYTHING FROM THE 40-PIN HEADER FIRST: the header test drives its pins.
The EEPROM test writes the last 8 bytes of the AT24C02 and restores them afterwards.
The OLED test only writes to the display (it cannot read back): look at the screen.
"""
import ctypes
import mmap
import os
import select
import struct
import sys
import time

BIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pltest.bit")


# ---------------------------------------------------------------------------------------------------
# Register helpers
# ---------------------------------------------------------------------------------------------------
class Regs:
    """32-bit register window through /dev/mem (independent of the PYNQ IP drivers).

    Accesses are single 32-bit loads/stores through a ctypes array. (struct.pack_into on an mmap can compile to
    byte-wide stores, and writing a DMA LENGTH register byte by byte starts transfers with garbage lengths.)
    """

    def __init__(self, phys, size=0x10000):
        self._fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        self._m = mmap.mmap(self._fd, size, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=phys)
        self._w = (ctypes.c_uint32 * (size // 4)).from_buffer(self._m)

    def rd(self, off):
        return self._w[off >> 2]

    def wr(self, off, val):
        self._w[off >> 2] = val & 0xFFFFFFFF


class Gpio(Regs):
    """AXI GPIO: DATA 0x0, TRI 0x4 (1 = input), DATA2 0x8, TRI2 0xC."""

    def data(self):
        return self.rd(0x0)

    def out(self, v):
        self.wr(0x0, v)

    def tri(self, v):
        self.wr(0x4, v)

    def data2(self):
        return self.rd(0x8)


def uio_named(name):
    """/dev/uioN with the given sysfs name (the stock device tree has one called 'fabric' for IRQ_F2P[0])."""
    base = "/sys/class/uio"
    for d in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        try:
            if open(f"{base}/{d}/name").read().strip() == name:
                return "/dev/" + d
        except OSError:
            pass
    return None


def uio_for(phys):
    """/dev/uioN of the device-tree node with unit address phys (maps are page aligned, so two nodes in one
    page report the same map address; the platform device name keeps the real unit address)."""
    base = "/sys/class/uio"
    for d in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        try:
            if os.path.basename(os.path.realpath(f"{base}/{d}/device")).startswith("%08x" % phys):
                return "/dev/" + d
        except OSError:
            pass
    for d in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        try:
            a = int(open(f"{base}/{d}/maps/map0/addr").read().strip(), 16)
        except OSError:
            continue
        if a == phys:
            return "/dev/" + d
    return None


class Irq:
    """Blocking wait on a UIO interrupt."""

    def __init__(self, dev):
        self.fd = os.open(dev, os.O_RDWR)

    def arm(self):
        os.write(self.fd, struct.pack("<I", 1))

    def wait(self, timeout):
        r, _, _ = select.select([self.fd], [], [], timeout)
        if not r:
            return None
        return struct.unpack("<I", os.read(self.fd, 4))[0]

    def close(self):
        os.close(self.fd)


class Skip(Exception):
    pass


class Result:
    def __init__(self, status, text):
        self.status, self.text = status, text


# ---------------------------------------------------------------------------------------------------
# Overlay
# ---------------------------------------------------------------------------------------------------
OV = None
ADDR = {}


def load_overlay():
    global OV
    from pynq import Overlay
    OV = Overlay(BIT)
    # Base addresses come from the .hwh itself: PYNQ's ip_dict reports a wrong address for AXI GPIOs that have an
    # external tri-state interface.
    import re
    hwh = open(BIT.replace(".bit", ".hwh")).read()
    for name in ("leds", "keys", "hdr0", "hdr1", "eeprom", "oled", "ple", "fm0", "fm1", "fm2", "status",
                 "timer", "dma"):
        m = re.search(r'<MEMRANGE[^>]*BASEVALUE="(0x[0-9A-Fa-f]+)"[^>]*INSTANCE="%s"[^>]*MEMTYPE="REGISTER"' % name, hwh)
        ADDR[name] = int(m.group(1), 16)
    return OV


def gpio(name):
    return Gpio(ADDR[name])


# ---------------------------------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------------------------------
def t_leds_keys():
    leds, keys = gpio("leds"), gpio("keys")
    for pat in (1, 2, 4, 8, 0xF, 0):
        leds.out(pat)
        if leds.data() != pat:
            return Result("FAIL", f"LED register readback {leds.data():#x} != {pat:#x}")
        time.sleep(0.15)
    k = keys.data() & 3
    if k != 3:
        return Result("WARN", f"a key reads pressed (value {k:#04b}); release KEY2/KEY3 and rerun")
    return Result("PASS", "LED registers ok (watch LED1..4 chase), KEY2/KEY3 idle high. "
                          "Press a key during `python3 pltest_run.py keys_live` to see it.")


def t_keys_live():
    keys = gpio("keys")
    print("   press KEY2 / KEY3 within 10 s ...")
    seen = 0
    t0 = time.time()
    while time.time() - t0 < 10 and seen != 3:
        seen |= (~keys.data()) & 3
        time.sleep(0.01)
    if seen == 3:
        return Result("PASS", "both keys seen pressed")
    return Result("WARN", f"keys seen pressed bitmask {seen:#04b} (3 = both)")


# 40-pin header: right column pins 2..18 are bits 0..16, left column pins 39..23 are bits 17..33.
HDR_PIN = list(range(2, 19)) + list(range(39, 22, -1))


def t_header():
    h0, h1 = gpio("hdr0"), gpio("hdr1")

    def drive(bit, val):
        """Drive one header bit, all others inputs; return the 34-bit pad state."""
        t0, t1 = 0xFFFFFFFF, 0x3
        o0 = o1 = 0
        if bit < 32:
            t0 &= ~(1 << bit)
            o0 = val << bit
        else:
            t1 &= ~(1 << (bit - 32))
            o1 = val << (bit - 32)
        h0.out(o0)
        h1.out(o1)
        h0.tri(t0)
        h1.tri(t1)
        time.sleep(0.0005)
        return h0.data() | ((h1.data() & 3) << 32)

    stuck, shorts = [], []
    levels = {}
    for b in range(34):
        hi, lo = drive(b, 1), drive(b, 0)
        levels[b] = (hi, lo)
        if not (hi >> b) & 1:
            stuck.append(f"pin {HDR_PIN[b]} cannot go high")
        if (lo >> b) & 1:
            stuck.append(f"pin {HDR_PIN[b]} cannot go low")
        diff = (hi ^ lo) & ~(1 << b)
        for j in range(34):
            if (diff >> j) & 1:
                shorts.append(f"pin {HDR_PIN[b]} drags pin {HDR_PIN[j]}")
    h0.tri(0xFFFFFFFF)
    h1.tri(0x3)
    problems = stuck + shorts
    if problems:
        return Result("FAIL", "; ".join(problems[:8]) + (" ..." if len(problems) > 8 else ""))
    return Result("PASS", "all 34 header signals drive high and low, no coupling between pins")


def t_clocks():
    from pynq import Clocks
    st = gpio("status")
    if not st.data() & 1:
        return Result("FAIL", "clock wizard (MMCM) not locked")
    ref = Clocks.fclk0_mhz * 1e6
    notes, bad = [], []

    def counts(skip=1):
        # A gate that was already running when a clock changed mixes old and new frequency, so let `skip` gates
        # finish and read the one after.
        for _ in range(skip + 1):
            g = st.data2()
            while st.data2() == g:
                time.sleep(0.005)
        c = []
        for n in ("fm0", "fm1", "fm2"):
            r = gpio(n)
            c += [r.data(), r.data2()]
        return c

    def hz(count):
        return count * ref / 10_000_000.0  # gate = 10,000,000 reference cycles

    for idx, want, label in ((0, 50, "PL osc -> MMCM 50"), (1, 100, "MMCM 100"), (2, 150, "MMCM 150"),
                             (3, 200, "MMCM 200")):
        got = hz(counts()[idx]) / 1e6
        err = (got - want) / want * 100
        notes.append(f"{label} MHz: {got:.3f} ({err:+.3f} %)")
        if abs(err) > 0.1:
            bad.append(label)
    for fclk, attr, idx, sweep in (("FCLK1", "fclk1_mhz", 4, (50, 100, 125, 200)),
                                   ("FCLK2", "fclk2_mhz", 5, (75, 100, 150))):
        for want in sweep:
            setattr(Clocks, attr, want)
            time.sleep(0.05)
            actual = getattr(Clocks, attr)
            got = hz(counts()[idx]) / 1e6
            err = (got - actual) / actual * 100
            notes.append(f"{fclk} set {want} -> reports {actual:.3f}, measured {got:.3f} ({err:+.3f} %)")
            if abs(err) > 0.5:
                bad.append(f"{fclk}@{want}")
    Clocks.fclk1_mhz = 50
    Clocks.fclk2_mhz = 75
    return Result("FAIL" if bad else "PASS", "; ".join(notes) + (f" | out of tolerance: {bad}" if bad else ""))


def t_timer_irq():
    dev = uio_named("fabric")                       # stock UIO node on IRQ_F2P[0]
    if not dev:
        raise Skip("no 'fabric' UIO device (IRQ_F2P[0]) in the device tree")
    tm = Regs(0x42800000)
    irq = Irq(dev)
    period_cycles = 1_000_000                       # 10 ms at 100 MHz
    n = 100
    tm.wr(0x0, 0)                                    # TCSR0: stop
    tm.wr(0x4, period_cycles)                        # TLR0
    tm.wr(0x0, 0x20)                                 # LOAD0
    t0 = time.time()
    tm.wr(0x0, 0xD2)                                 # ENT0 | ENIT0 | ARHT0 | UDT0
    got = 0
    for _ in range(n):
        irq.arm()
        if irq.wait(1.0) is None:
            break
        tm.wr(0x0, tm.rd(0x0) | 0x100)               # clear T0INT
        got += 1
    elapsed = time.time() - t0
    tm.wr(0x0, 0)
    irq.close()
    if got != n:
        return Result("FAIL", f"only {got}/{n} timer interrupts arrived")
    err = (elapsed - n * 0.01) / (n * 0.01) * 100
    return Result("PASS" if abs(err) < 3 else "WARN",
                  f"{n} interrupts in {elapsed:.4f} s (expected {n * 0.01:.2f} s, {err:+.2f} %) via {dev}")


def t_dma():
    from pynq import allocate
    import numpy as np
    d = Regs(ADDR["dma"])
    dev_m, dev_s = uio_for(0x40400000), uio_for(0x40400100)
    irq_m = Irq(dev_m) if dev_m else None
    irq_s = Irq(dev_s) if dev_s else None
    notes = []

    def reset():
        d.wr(0x00, 0x4)
        d.wr(0x30, 0x4)
        t0 = time.time()
        while (d.rd(0x00) & 4) or (d.rd(0x30) & 4):
            if time.time() - t0 > 1:
                raise RuntimeError("DMA reset did not complete")

    GUARD = 64 * 1024               # canary bytes after the destination: the DMA must not write past its length

    def run(nbytes, use_irq):
        src = allocate(shape=(nbytes,), dtype=np.uint8)
        dst = allocate(shape=(nbytes + GUARD,), dtype=np.uint8)
        src[:] = np.frombuffer(os.urandom(nbytes), dtype=np.uint8)
        dst[:] = 0xA5
        src.flush()
        dst.flush()
        reset()
        cr = 0x1 | (0x1000 if use_irq else 0)
        if use_irq:
            irq_m.arm()
            irq_s.arm()
        d.wr(0x30, cr)
        d.wr(0x48, dst.physical_address)
        d.wr(0x58, nbytes)                            # S2MM first so it is ready for the stream
        d.wr(0x00, cr)
        d.wr(0x18, src.physical_address)
        t0 = time.time()
        d.wr(0x28, nbytes)
        if use_irq:
            if irq_s.wait(5) is None:
                src.freebuffer()
                dst.freebuffer()
                raise RuntimeError("no S2MM interrupt")
            irq_m.wait(1)
        else:
            while not (d.rd(0x34) & 0x1000):          # IOC_Irq (set on completion even with the interrupt masked)
                if time.time() - t0 > 5:
                    raise RuntimeError("transfer timed out (SR=%#x/%#x)" % (d.rd(0x04), d.rd(0x34)))
        dt = time.time() - t0
        err = (d.rd(0x04) & 0x70) | (d.rd(0x34) & 0x70)
        got = d.rd(0x58)                              # bytes the S2MM channel received
        d.wr(0x04, 0x7000)
        d.wr(0x34, 0x7000)
        dst.invalidate()
        ok = bool(np.array_equal(src, dst[:nbytes])) and got == nbytes
        overrun = int(np.count_nonzero(dst[nbytes:] != 0xA5))
        src.freebuffer()
        dst.freebuffer()
        return ok and overrun == 0, dt, err

    try:
        for nbytes, use_irq in ((64, False), (4096, True), (1 << 20, True), (4 << 20, False), (4 << 20, True)):
            ok, dt, err = run(nbytes, use_irq and irq_m is not None)
            notes.append(f"{nbytes >> 10 if nbytes >= 1024 else nbytes}{'KiB' if nbytes >= 1024 else 'B'}"
                         f"{' irq' if use_irq and irq_m else ''}: {'ok' if ok else 'MISMATCH'}"
                         f" {nbytes / dt / 1e6:.0f} MB/s")
            if not ok or err:
                return Result("FAIL", "; ".join(notes) + f" (DMASR error bits {err:#x})")
    except RuntimeError as e:
        return Result("FAIL", "; ".join(notes) + f" | {e}")
    finally:
        for q in (irq_m, irq_s):
            if q:
                q.close()
    if not (irq_m and irq_s):
        notes.append("(interrupt part skipped: pltest.dtbo not loaded)")
        return Result("WARN", "; ".join(notes))
    return Result("PASS", "MM2S -> S2MM loopback, DMA data intact, interrupts delivered: " + "; ".join(notes))


# --- AT24C02 on a bit-banged I2C bus ------------------------------------------------------------------
class I2C:
    SCL, SDA = 1, 2                                  # bit masks of the eeprom GPIO (SCL = F19, SDA = F20)

    def __init__(self):
        self.g = gpio("eeprom")
        self._set(1, 1)

    def _set(self, scl, sda):
        # The board has a pull-up on SDA (F20) but none on SCL (F19), and this master is the only one, so SCL is
        # driven push-pull. SDA is open drain: data bit 1 is always 0, TRI bit 1 high = released (pulled up).
        self.g.out(1 if scl else 0)
        self.g.tri(0x2 if sda else 0x0)
        time.sleep(0.00002)

    def sda(self):
        return (self.g.data() >> 1) & 1

    def start(self):
        self._set(1, 1)
        self._set(1, 0)
        self._set(0, 0)

    def stop(self):
        self._set(0, 0)
        self._set(1, 0)
        self._set(1, 1)

    def wbyte(self, b):
        for i in range(7, -1, -1):
            bit = (b >> i) & 1
            self._set(0, bit)
            self._set(1, bit)
            self._set(0, bit)
        self._set(0, 1)                              # release SDA for ACK
        self._set(1, 1)
        ack = self.sda() == 0
        self._set(0, 1)
        return ack

    def rbyte(self, ack):
        v = 0
        self._set(0, 1)
        for _ in range(8):
            self._set(1, 1)
            v = (v << 1) | self.sda()
            self._set(0, 1)
        self._set(0, 0 if ack else 1)
        self._set(1, 0 if ack else 1)
        self._set(0, 0 if ack else 1)
        self._set(0, 1)
        return v

    def probe(self, addr7):
        self.start()
        ok = self.wbyte(addr7 << 1)
        self.stop()
        return ok

    def read(self, addr7, off, n):
        self.start()
        if not (self.wbyte(addr7 << 1) and self.wbyte(off)):
            self.stop()
            raise IOError("no ACK on read setup")
        self.start()
        if not self.wbyte((addr7 << 1) | 1):
            self.stop()
            raise IOError("no ACK on read address")
        data = [self.rbyte(i < n - 1) for i in range(n)]
        self.stop()
        return data

    def write(self, addr7, off, data):
        self.start()
        ok = self.wbyte(addr7 << 1) and self.wbyte(off) and all(self.wbyte(b) for b in data)
        self.stop()
        if not ok:
            raise IOError("no ACK on write")
        t0 = time.time()
        while not self.probe(addr7):                 # ack polling while the write cycle runs
            if time.time() - t0 > 0.1:
                raise IOError("write cycle did not finish")


def t_eeprom():
    bus = I2C()
    time.sleep(0.01)
    if bus.sda() != 1:
        return Result("FAIL", "SDA stuck low (no pull-up or a device holds the bus)")
    found = [a for a in range(0x08, 0x78) if bus.probe(a)]
    if not found:
        return Result("FAIL", "no I2C device answers (checked 0x08..0x77)")
    notes = ["devices at " + ", ".join(f"{a:#04x}" for a in found)]
    a = 0x50
    if a not in found:
        return Result("FAIL", notes[0] + "; expected the AT24C02 at 0x50")
    first = bus.read(a, 0x00, 16)
    notes.append("bytes 0x00..0x0F: " + " ".join(f"{b:02x}" for b in first))
    saved = bus.read(a, 0xF8, 8)
    pattern = [0xA5, 0x5A, 0x3C, 0xC3, 0x01, 0xFE, 0x80, 0x7F]
    try:
        bus.write(a, 0xF8, pattern)
        got = bus.read(a, 0xF8, 8)
    finally:
        try:
            bus.write(a, 0xF8, saved)
        except IOError:
            pass
    restored = bus.read(a, 0xF8, 8)
    if got != pattern:
        return Result("FAIL", "; ".join(notes) + f"; write/readback mismatch {got} (is WP tied high?)")
    if restored != saved:
        return Result("FAIL", "; ".join(notes) + "; could NOT restore the original bytes at 0xF8")
    notes.append("write/readback of 8 bytes at 0xF8 ok, original bytes restored")
    return Result("PASS", "; ".join(notes))


# --- SSD1306 OLED over a bit-banged SPI ------------------------------------------------------------------
class Oled:
    SCLK, MOSI, DC, RES = 1, 2, 4, 8

    def __init__(self):
        self.g = gpio("oled")
        self.v = 0

    def _o(self, v):
        self.v = v
        self.g.out(v)

    def _byte(self, b, dc):
        base = (self.v & self.RES) | (self.DC if dc else 0)
        for i in range(7, -1, -1):
            bit = self.MOSI if (b >> i) & 1 else 0
            self._o(base | bit)
            self._o(base | bit | self.SCLK)
        self._o(base)

    def cmd(self, *bs):
        for b in bs:
            self._byte(b, 0)

    def init(self):
        self._o(0)
        time.sleep(0.01)
        self._o(self.RES)
        time.sleep(0.01)
        self.cmd(0xAE, 0xD5, 0x80, 0xA8, 0x3F, 0xD3, 0x00, 0x40, 0x8D, 0x14, 0x20, 0x00, 0xA1, 0xC8,
                 0xDA, 0x12, 0x81, 0xCF, 0xD9, 0xF1, 0xDB, 0x40, 0xA4, 0xA6, 0xAF)

    def show(self, fb):
        self.cmd(0x21, 0, 127, 0x22, 0, 7)
        for b in fb:
            self._byte(b, 1)


FONT = {  # 5x7, columns, bit0 = top
    "Z": [0x61, 0x51, 0x49, 0x45, 0x43], "Y": [0x07, 0x08, 0x70, 0x08, 0x07], "N": [0x7F, 0x04, 0x08, 0x10, 0x7F],
    "Q": [0x3E, 0x41, 0x51, 0x21, 0x5E], "M": [0x7F, 0x02, 0x0C, 0x02, 0x7F], "I": [0x00, 0x41, 0x7F, 0x41, 0x00],
    "P": [0x7F, 0x09, 0x09, 0x09, 0x06], "L": [0x7F, 0x40, 0x40, 0x40, 0x40], "O": [0x3E, 0x41, 0x41, 0x41, 0x3E],
    "K": [0x7F, 0x08, 0x14, 0x22, 0x41], " ": [0, 0, 0, 0, 0],
}


def t_oled():
    o = Oled()
    o.init()
    fb = bytearray(1024)

    def px(x, y):
        if 0 <= x < 128 and 0 <= y < 64:
            fb[(y // 8) * 128 + x] |= 1 << (y % 8)

    for x in range(128):                              # border
        px(x, 0), px(x, 63)
    for y in range(64):
        px(0, y), px(127, y)
    for i in range(64):                               # diagonals
        px(i * 2, i), px(127 - i * 2, i)
    cx = 30
    for ch in "ZYNQ MINI PL OK":
        for col, bits in enumerate(FONT.get(ch, FONT[" "])):
            for r in range(7):
                if (bits >> r) & 1:
                    px(cx + col, 28 + r)
        cx += 6
    o.show(fb)
    return Result("MANUAL", "pattern sent: border, two diagonals and the text 'ZYNQ MINI PL OK'. "
                            "Look at the OLED to confirm (the display cannot be read back).")


# --- PL Ethernet PHY management (MDC/MDIO), no cable needed to read the ID ------------------------------
def t_ple_phy():
    g = gpio("ple")
    RST, MDC, MDIO = 1, 2, 4
    state = {"o": 0}

    def setb(rst=None, mdc=None, mdio=None, mdio_out=True):
        o = state["o"]
        for mask, val in ((RST, rst), (MDC, mdc), (MDIO, mdio)):
            if val is not None:
                o = (o | mask) if val else (o & ~mask)
        state["o"] = o
        g.out(o)
        g.tri(0x0 if mdio_out else MDIO)              # bits 0,1 always outputs; bit 2 output only when driving

    def clk(bit_out=None):
        if bit_out is None:
            setb(mdc=0, mdio_out=False)
            setb(mdc=1, mdio_out=False)
            v = (g.data() >> 2) & 1
            setb(mdc=0, mdio_out=False)
            return v
        setb(mdc=0, mdio=bit_out)
        setb(mdc=1, mdio=bit_out)
        setb(mdc=0, mdio=bit_out)

    def read(phy, reg):
        for _ in range(32):
            clk(1)
        for b in (0, 1, 1, 0):                        # start 01, read 10
            clk(b)
        for i in range(4, -1, -1):
            clk((phy >> i) & 1)
        for i in range(4, -1, -1):
            clk((reg >> i) & 1)
        zero = clk(None)                              # turnaround: the PHY drives 0 (as in Linux's mdio-bitbang, one clock)
        v = 0
        for _ in range(16):
            v = (v << 1) | clk(None)
        return v, zero == 0

    setb(rst=0, mdc=0, mdio=1)
    time.sleep(0.02)
    setb(rst=1)
    time.sleep(0.2)
    found = None
    for phy in range(32):
        r2, ok = read(phy, 2)
        if ok and r2 not in (0x0000, 0xFFFF):
            r3, _ = read(phy, 3)
            found = (phy, r2, r3)
            break
    g.tri(0x7)
    if not found:
        return Result("FAIL", "no PHY answered on MDIO (addresses 0..31)")
    phy, r2, r3 = found
    oui_ok = r2 == 0x001C
    r1, _ = read(phy, 1)
    r1, _ = read(phy, 1)                               # link bit is latched; read twice
    physr, _ = read(phy, 0x11)
    link = "link up" if r1 & 4 else "no link (no cable, expected)"
    text = (f"PHY at address {phy}: ID {r2:#06x}:{r3:#06x} "
            f"({'Realtek RTL8211E, OUI matches' if oui_ok and (r3 >> 4) == 0xC91 else 'unexpected ID'}); "
            f"status {r1:#06x} {link}; PHYSR {physr:#06x}")
    return Result("PASS" if oui_ok else "FAIL", text)


TESTS = [("leds_keys", t_leds_keys), ("header", t_header), ("clocks", t_clocks), ("timer_irq", t_timer_irq),
         ("dma", t_dma), ("eeprom", t_eeprom), ("oled", t_oled), ("ple_phy", t_ple_phy)]
EXTRA = {"keys_live": t_keys_live}


def main(argv):
    if "--list" in argv:
        print(" ".join(n for n, _ in TESTS + list(EXTRA.items())))
        return 0
    if os.geteuid() != 0:
        print("run as root (sudo -i)")
        return 2
    want = [a for a in argv if not a.startswith("-")]
    table = dict(TESTS)
    table.update(EXTRA)
    names = want or [n for n, _ in TESTS]
    for n in names:
        if n not in table:
            print(f"unknown test {n!r}; --list shows the names")
            return 2
    print(f"loading {BIT} ...")
    load_overlay()
    worst = 0
    for n in names:
        print(f"== {n}")
        try:
            r = table[n]()
        except Skip as e:
            r = Result("SKIP", str(e))
        except Exception as e:                          # a crashing test is a failing test
            r = Result("FAIL", f"{type(e).__name__}: {e}")
        print(f"   {r.status}: {r.text}")
        worst = max(worst, {"PASS": 0, "MANUAL": 0, "SKIP": 0, "WARN": 1, "FAIL": 2}[r.status])
    print("\nresult:", ["all passed", "passed with warnings", "FAILURES"][worst])
    return 0 if worst < 2 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
