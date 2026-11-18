import mmap, os, ctypes, time
from pynq import Clocks
Clocks.fclk0_mhz = 100
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x40000000)
a = (ctypes.c_uint32 * 0x400).from_buffer(m)
rd = lambda o: a[o // 4]
print("ID %#x locked=%d" % (rd(0), rd(0x2C)))
T = 2**20 / 100e6
for name, off, exp in (("clk50 ", 0x28, 50), ("pclk  ", 0x20, 25), ("clk5x ", 0x24, 125)):
    v = [rd(off) for _ in range(3)]
    print("%s counts/window %s -> %.3f MHz (want %d)" % (name, v, v[-1] / T / 1e6, exp))
