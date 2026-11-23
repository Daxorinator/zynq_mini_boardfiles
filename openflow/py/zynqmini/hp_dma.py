"""The PL DMA engine of the hp_dma / zm_base overlays through the PS HP0 port (copy or checksum of 128-byte-aligned buffers), with polling or interrupt completion.
    ol = Overlay("zm_base"); dma = HpDma(ol)
    a = allocate((4096,), "uint8"); b = allocate((4096,), "uint8"); a[:] = 7
    dma.copy(a, b)"""
import time

class DmaError(RuntimeError): pass

class HpDma:
    def __init__(self, overlay, prefix=""):
        r = overlay.registers
        pick = lambda n: r[prefix + n] if prefix + n in r else r["DMA_" + n]
        self.src, self.dst, self.len, self.ctrl, self.status, self.csum, self.cycles, self.bytes = (pick(n) for n in ("SRC", "DST", "LEN", "CTRL", "STATUS", "CHECKSUM", "CYCLES", "BYTES"))
        self.overlay = overlay
    @staticmethod
    def _phys(x): return x if isinstance(x, int) else x.phys_addr
    def _run(self, src, dst, nbytes, flags, timeout, irq):
        self.ctrl.write(4)                                          # clear done / error
        self.src.write(self._phys(src)); self.dst.write(self._phys(dst) if dst is not None else 0); self.len.write(nbytes)
        if irq is not None: irq.rearm(); flags |= 8
        self.ctrl.write(flags | 1)
        if irq is not None:
            if irq.wait(timeout) is None: raise DmaError("DMA timed out")
        else:
            t0 = time.time()
            while not self.status.read() & 2:
                if time.time() - t0 > timeout: raise DmaError("DMA timed out")
        st = self.status.read(); self.ctrl.write(4)
        if st & 4: raise DmaError("DMA error (bus error response, or a misaligned address/length was rejected)")
        return st
    def copy(self, src, dst, nbytes=None, timeout=5.0, irq=None):
        """Copy nbytes (default: the size of src) from physical buffer src to dst; addresses and length must be multiples of 128."""
        n = nbytes if nbytes is not None else getattr(src, "size", None) or src.array.nbytes
        self._run(src, dst, n, 0, timeout, irq); return n
    def checksum(self, src, nbytes=None, timeout=5.0, irq=None):
        """Sum of all 32-bit words of src, computed by the PL without writing anything."""
        n = nbytes if nbytes is not None else getattr(src, "size", None) or src.array.nbytes
        self._run(src, None, n, 2, timeout, irq); return self.csum.read()
