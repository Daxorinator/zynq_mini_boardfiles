#!/usr/bin/env python3
"""Linux-side test for hp_dma.bin (run on the board as root with the PYNQ venv: XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3).
The PS fills buffers in DDR, programs the PL block over GP0 and polls its STATUS register (the "done" sentinel); the PL moves the data
through the HP0 port and the PS checks the result. Ends with a line "HP_DMA RESULT: PASS" or "FAIL"."""
import mmap, os, select, struct, sys, time
import numpy as np
from pynq import Clocks, allocate

Clocks.fclk0_mhz = 100
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x40000000)
rd = lambda o: int.from_bytes(m[o:o + 4], "little")
wr = lambda o, v: m.__setitem__(slice(o, o + 4), (v & 0xFFFFFFFF).to_bytes(4, "little"))
SRC, DST, LEN, CTRL, STATUS, CSUM, CYC, DONE = 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20, 0x24
ok = True
def check(cond, msg):
    global ok
    print(("  ok   " if cond else "  FAIL ") + msg)
    ok = ok and cond

check(rd(0) == 0x48504431, "block ID %#x (want 0x48504431 'HPD1')" % rd(0))
def run(src, dst, n, mode, timeout=3.0):
    wr(CTRL, 4)                                   # clear done/err
    wr(SRC, src); wr(DST, dst); wr(LEN, n)
    wr(CTRL, 1 | (mode << 1))                     # start
    t0 = time.time()
    while not (rd(STATUS) & 2):                   # sentinel: done bit
        if time.time() - t0 > timeout: return None
    return rd(STATUS)

rng = np.random.default_rng(12345)
for n in (128, 4096, 1 << 20, 8 << 20):
    src = allocate(shape=(n,), dtype=np.uint8)
    dst = allocate(shape=(n + 256,), dtype=np.uint8)
    src[:] = rng.integers(0, 256, n, dtype=np.uint8); dst[:] = 0xA5
    src.flush(); dst.flush()
    st = run(src.physical_address, dst.physical_address, n, 0)
    if st is None: check(False, "copy %d bytes: timeout (status %#x)" % (n, rd(STATUS))); break
    dst.invalidate()
    check(st & 4 == 0, "copy %d bytes: no AXI error" % n)
    check(bytes(dst[:n]) == bytes(src), "copy %d bytes: destination matches source" % n)
    check(bool((dst[n:] == 0xA5).all()), "copy %d bytes: no write past the end" % n)
    want = int(np.asarray(src).view(np.uint32).sum(dtype=np.uint64)) & 0xFFFFFFFF
    check(rd(CSUM) == want, "copy %d bytes: PL checksum %#x == %#x" % (n, rd(CSUM), want))
    check(rd(DONE) == n, "copy %d bytes: bytes-done counter %d" % (n, rd(DONE)))
    print("       %d cycles at 100 MHz" % rd(CYC))
    src.freebuffer(); dst.freebuffer()

n = 1 << 20
src = allocate(shape=(n,), dtype=np.uint8); src[:] = rng.integers(0, 256, n, dtype=np.uint8); src.flush()
st = run(src.physical_address, 0, n, 1)
want = int(np.asarray(src).view(np.uint32).sum(dtype=np.uint64)) & 0xFFFFFFFF
check(st is not None and rd(CSUM) == want, "checksum-only mode over 1 MiB: %#x == %#x" % (rd(CSUM), want))
# ---- interrupt: IRQ_F2P[0] reaches Linux through the stock UIO node named "fabric" (no overlay needed) ----
def uio_named(name):
    for d in sorted(os.listdir("/sys/class/uio")):
        if open("/sys/class/uio/%s/name" % d).read().strip() == name: return "/dev/" + d
uio = uio_named("fabric")
check(uio is not None, "UIO device 'fabric' present (%s)" % uio)
if uio:
    fdu = os.open(uio, os.O_RDWR)
    n = 1 << 20
    src = allocate(shape=(n,), dtype=np.uint8); dst = allocate(shape=(n,), dtype=np.uint8)
    src[:] = rng.integers(0, 256, n, dtype=np.uint8); dst[:] = 0; src.flush(); dst.flush()
    wr(CTRL, 4)                                    # clear done, interrupt disabled
    os.write(fdu, struct.pack("I", 1))             # arm the UIO interrupt
    wr(SRC, src.physical_address); wr(DST, dst.physical_address); wr(LEN, n)
    r, _, _ = select.select([fdu], [], [], 0.05)
    check(not r, "no interrupt before the transfer starts")
    wr(CTRL, 1 | (1 << 3))                         # start, interrupt enable
    r, _, _ = select.select([fdu], [], [], 3.0)    # sleep until the PL raises IRQ_F2P[0]
    check(bool(r), "interrupt arrived (PS slept in select() until the PL finished)")
    if r:
        cnt = struct.unpack("I", os.read(fdu, 4))[0]
        check(cnt >= 1 and (rd(STATUS) & 2), "interrupt count %d, STATUS done" % cnt)
        dst.invalidate()
        check(bytes(dst) == bytes(src), "data copied correctly when the interrupt fired")
    wr(CTRL, 4)                                    # clear done and interrupt enable
    os.write(fdu, struct.pack("I", 1))
    r, _, _ = select.select([fdu], [], [], 0.3)
    check(not r, "no stray interrupt after clearing")
    os.close(fdu)
print("HP_DMA RESULT: %s" % ("PASS" if ok else "FAIL"))
sys.exit(0 if ok else 1)
