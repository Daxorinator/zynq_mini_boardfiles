#!/usr/bin/env python3
"""hp_dma.bin through the PYNQ-free zynqmini library (run on the board as root, kernel with CONFIG_DMABUF_HEAPS_CMA):
    cd openflow/py && python3 tests/hp_dma_test.py ../pl/build/hp_dma/hp_dma.bin
Same checks as openflow/pl/hp_dma/hp_dma_test.py, without PYNQ: contiguous buffers from dma-heap, FCLK0 set through the SLCR,
the interrupt through UIO. Ends with "ZYNQMINI HP_DMA RESULT: PASS" or "FAIL"."""
import os, random, struct, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from zynqmini import load_bitstream, MMIO, set_fclk, fclk_mhz, allocate, UioIrq

SRC, DST, LEN, CTRL, STATUS, CSUM, CYC, DONE = 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20, 0x24
ok = True
def check(c, m):
    global ok; ok = ok and bool(c); print(("  ok   " if c else "  FAIL ") + m)

print("fpga state:", load_bitstream(sys.argv[1]))
print("FCLK0 set to %.2f MHz (IO PLL %.1f MHz)" % (set_fclk(0, 100), __import__("zynqmini").pll_mhz(2)))
regs = MMIO(0x40000000, 0x1000)
check(regs[0] == 0x48504431, "block ID %#x" % regs[0])

def run(src, dst, n, mode, timeout=3.0):
    regs[CTRL] = 4; regs[SRC] = src; regs[DST] = dst; regs[LEN] = n; regs[CTRL] = 1 | (mode << 1)
    t0 = time.time()
    while not regs[STATUS] & 2:
        if time.time() - t0 > timeout: return None
    return regs[STATUS]

rnd = random.Random(7)
for n in (128, 4096, 1 << 20, 8 << 20):
    a, b = allocate(n), allocate(n + 256)
    data = rnd.randbytes(n)
    a.mm[:n] = data; b.mm[:n + 256] = b"\xa5" * (n + 256); a.flush(); b.flush()
    st = run(a.phys_addr, b.phys_addr, n, 0)
    if st is None: check(False, "copy %d bytes: timeout" % n); break
    b.invalidate()
    check(st & 4 == 0 and bytes(b.mm[:n]) == data, "copy %d bytes: identical, no AXI error" % n)
    check(bytes(b.mm[n:n + 256]) == b"\xa5" * 256, "copy %d bytes: nothing written past the end" % n)
    want = sum(struct.unpack("<%dI" % (n // 4), data)) & 0xFFFFFFFF
    check(regs[CSUM] == want and regs[DONE] == n, "copy %d bytes: PL checksum and byte counter" % n)
    a.close(); b.close()

irq = UioIrq(); n = 1 << 20
a, b = allocate(n), allocate(n); data = rnd.randbytes(n); a.mm[:n] = data; b.mm[:n] = bytes(n); a.flush(); b.flush()
regs[CTRL] = 4; irq.rearm()
check(irq.wait(0.05) is None, "no interrupt before the transfer")
regs[SRC] = a.phys_addr; regs[DST] = b.phys_addr; regs[LEN] = n; regs[CTRL] = 1 | (1 << 3)
cnt = irq.wait(3.0)
check(cnt is not None, "interrupt arrived (slept until the PL finished)")
b.invalidate(); check(bytes(b.mm[:n]) == data, "data correct when the interrupt fired")
regs[CTRL] = 4; irq.rearm(); check(irq.wait(0.3) is None, "no stray interrupt after clearing")
print("ZYNQMINI HP_DMA RESULT: %s" % ("PASS" if ok else "FAIL")); sys.exit(0 if ok else 1)
