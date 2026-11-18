"""Physically contiguous, uncached DMA buffers for PL masters, from the zmbuf kernel driver (openflow/linux/zmbuf, /dev/zmbuf).
The CPU mapping is write-combined/uncached, so no cache maintenance is needed before or after the PL touches the memory
(`flush()` and `invalidate()` exist only so code written for cached buffers keeps working)."""
import mmap, os, struct, fcntl

ZMBUF_ALLOC = 0xC0105A01            # _IOWR('Z', 1, struct { u64 size; u64 phys; })
ZMBUF_FREE = 0x40105A02             # _IOW('Z', 2, same)
DEV = "/dev/zmbuf"

class Buffer:
    def __init__(self, nbytes):
        if not os.path.exists(DEV):
            raise FileNotFoundError("%s missing: load the zmbuf kernel module (insmod zmbuf.ko)" % DEV)
        self.fd = os.open(DEV, os.O_RDWR)
        req = bytearray(struct.pack("QQ", nbytes, 0))
        fcntl.ioctl(self.fd, ZMBUF_ALLOC, req)
        self.phys_addr = struct.unpack("QQ", bytes(req))[1]
        self.size = (nbytes + 4095) & ~4095
        self.mm = mmap.mmap(self.fd, self.size, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=self.phys_addr)
    def flush(self): pass
    def invalidate(self): pass
    def array(self, dtype):
        import numpy as np
        return np.frombuffer(self.mm, dtype=dtype)
    def close(self):
        self.mm.close()
        try: fcntl.ioctl(self.fd, ZMBUF_FREE, struct.pack("QQ", 0, self.phys_addr))
        finally: os.close(self.fd)

def allocate(nbytes): return Buffer(nbytes)
