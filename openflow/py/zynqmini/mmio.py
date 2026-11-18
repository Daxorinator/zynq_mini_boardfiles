"""Memory-mapped register access through /dev/mem (needs root and a kernel without CONFIG_STRICT_DEVMEM)."""
import mmap, os

class MMIO:
    """Window of `size` bytes at physical address `phys`. Accesses are real 32-bit loads/stores."""
    def __init__(self, phys, size=0x1000):
        self.phys, self.size = phys, size
        base = phys & ~0xFFF; self._off = phys - base
        self._fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        self._mm = mmap.mmap(self._fd, size + self._off, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=base)
        self._w = memoryview(self._mm).cast("I")
    def _idx(self, off):
        if off & 3 or not 0 <= off < self.size: raise ValueError("bad register offset %#x" % off)
        return (self._off + off) >> 2
    def read(self, off): return self._w[self._idx(off)]
    def write(self, off, val): self._w[self._idx(off)] = val & 0xFFFFFFFF
    def __getitem__(self, off): return self.read(off)
    def __setitem__(self, off, val): self.write(off, val)
    def close(self):
        self._w.release(); self._mm.close(); os.close(self._fd)
