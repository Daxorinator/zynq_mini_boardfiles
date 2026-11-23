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
    def __enter__(self): return self
    def __exit__(self, *a): self.close()
    def close(self):
        self.mm.close()
        try: fcntl.ioctl(self.fd, ZMBUF_FREE, struct.pack("QQ", 0, self.phys_addr))
        finally: os.close(self.fd)

class ContigArray:
    """numpy-style access to a contiguous buffer: `a = allocate((1024,), "uint32")`; `a.phys_addr` is what the PL needs. Behaves like an ndarray through `a.array`."""
    def __init__(self, shape, dtype):
        import numpy as np
        shape = (shape,) if isinstance(shape, int) else tuple(shape)
        self.buffer = Buffer(int(np.prod(shape)) * np.dtype(dtype).itemsize)
        self.array = self.buffer.array(dtype)[:int(np.prod(shape))].reshape(shape)
        self.phys_addr = self.physical_address = self.buffer.phys_addr
    def __getitem__(self, i): return self.array[i]
    def __setitem__(self, i, v): self.array[i] = v
    def __len__(self): return len(self.array)
    def __array__(self, dtype=None, copy=None): return self.array if dtype is None else self.array.astype(dtype)
    def free(self): self.buffer.close()
    close = free
    def __enter__(self): return self
    def __exit__(self, *a): self.free()

def allocate(nbytes_or_shape, dtype=None):
    """allocate(4096) -> Buffer (bytes via .mm);  allocate((256, 4), "uint32") -> ContigArray (numpy view in .array, same API idea as PYNQ's allocate)."""
    return Buffer(nbytes_or_shape) if dtype is None else ContigArray(nbytes_or_shape, dtype)
