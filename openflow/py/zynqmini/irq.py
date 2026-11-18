"""PL interrupt through a UIO device (the device tree has a node named "fabric" on IRQ_F2P[0])."""
import os, select, struct

def find_uio(name="fabric"):
    for d in sorted(os.listdir("/sys/class/uio")):
        if open("/sys/class/uio/%s/name" % d).read().strip() == name: return "/dev/" + d
    raise FileNotFoundError("no UIO device named %r" % name)

class UioIrq:
    def __init__(self, name="fabric"):
        self.fd = os.open(find_uio(name), os.O_RDWR); self.rearm()
    def rearm(self): os.write(self.fd, struct.pack("I", 1))        # re-enable the interrupt (the PL source must be cleared first)
    def wait(self, timeout=None):
        """Sleep until the interrupt fires; returns the event count, or None on timeout."""
        r, _, _ = select.select([self.fd], [], [], timeout)
        return struct.unpack("I", os.read(self.fd, 4))[0] if r else None
    def close(self): os.close(self.fd)
