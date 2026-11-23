"""PYNQ-style overlays without Vivado metadata: a bitstream plus a small JSON register map.

    from zynqmini import Overlay
    ol = Overlay("zm_base")              # finds zm_base.bin and zm_base.json, loads the bitstream, sets the FCLKs named in the map
    ol.LEDS = 0b0101                      # registers are attributes (reads and writes are real 32-bit accesses)
    print(hex(ol.ID), ol.KEYS)
    ol.registers                          # name -> Register (offset, access, description)
    buf = ol.allocate(4096)               # physically contiguous DMA buffer (see zynqmini.buffer)
    ol.irq().wait(1.0)                    # the PL interrupt (UIO)

Map file (JSON), next to the bitstream or in the zynqmini maps directory:
  {"name": "zm_base", "base": "0x40000000", "size": "0x1000", "fclk": {"0": 100.0}, "interrupt": "fabric",
   "registers": {"ID": {"offset": "0x00", "access": "r", "description": "..."}, ...},
   "arrays": {"RXBUF": {"offset": "0x400", "count": 320, "access": "r"}}}
access is one of r, w, rw, w1c (informational plus a guard: writing a read-only register raises)."""
import json, os
from .fpga import load_bitstream
from .mmio import MMIO
from .clocks import set_fclk
from .buffer import allocate as _allocate
from .irq import UioIrq

SEARCH = [p for p in os.environ.get("ZYNQMINI_PATH", "").split(":") if p] + ["/usr/share/zynqmini/bitstreams", "/opt/zynqmini/bitstreams", "."]
MAPS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "maps")

def _num(v): return int(v, 0) if isinstance(v, str) else int(v)

class Register:
    def __init__(self, mmio, name, offset, access="rw", description=""):
        self._mmio, self.name, self.offset, self.access, self.description = mmio, name, offset, access, description
    def read(self):
        if self.access == "w": raise PermissionError("%s is write-only" % self.name)
        return self._mmio.read(self.offset)
    def write(self, value):
        if self.access == "r": raise PermissionError("%s is read-only" % self.name)
        self._mmio.write(self.offset, value)
    value = property(read, write)
    def __repr__(self): return "Register(%s @ %#x, %s)" % (self.name, self.offset, self.access)

class RegisterArray:
    def __init__(self, mmio, name, offset, count, access="rw", stride=4):
        self._mmio, self.name, self.offset, self.count, self.access, self.stride = mmio, name, offset, count, access, stride
    def __len__(self): return self.count
    def __getitem__(self, i):
        if isinstance(i, slice): return [self[k] for k in range(*i.indices(self.count))]
        if not 0 <= i < self.count: raise IndexError(i)
        if self.access == "w": raise PermissionError("%s is write-only" % self.name)
        return self._mmio.read(self.offset + i * self.stride)
    def __setitem__(self, i, v):
        if not 0 <= i < self.count: raise IndexError(i)
        if self.access == "r": raise PermissionError("%s is read-only" % self.name)
        self._mmio.write(self.offset + i * self.stride, v)

def find_file(name, exts, dirs):
    if os.path.isfile(name): return name
    for d in dirs:
        for e in exts:
            p = os.path.join(d, name + e)
            if os.path.isfile(p): return p
    raise FileNotFoundError("%s%s not found in %s" % (name, exts, dirs))

class Overlay:
    def __init__(self, bitstream, map=None, download=True, mmio=None):
        bit = find_file(bitstream, ["", ".bin", ".bit"], SEARCH)
        stem = os.path.splitext(os.path.basename(bit))[0]
        mp = map or find_file(stem + ".json" if not bitstream.endswith(".json") else bitstream, [""], [os.path.dirname(os.path.abspath(bit))] + SEARCH + [MAPS])
        self.bitstream, self.map_file = bit, mp
        self.meta = json.load(open(mp)); self.name = self.meta.get("name", stem)
        if download:
            self.state = load_bitstream(bit)
            for n, mhz in self.meta.get("fclk", {}).items(): set_fclk(int(n), float(mhz))
        self.mmio = mmio or MMIO(_num(self.meta["base"]), _num(self.meta.get("size", 0x1000)))
        self.registers = {n: Register(self.mmio, n, _num(r["offset"]), r.get("access", "rw"), r.get("description", "")) for n, r in self.meta.get("registers", {}).items()}
        self.arrays = {n: RegisterArray(self.mmio, n, _num(a["offset"]), int(a["count"]), a.get("access", "rw"), int(a.get("stride", 4))) for n, a in self.meta.get("arrays", {}).items()}
    def __getattr__(self, name):
        d = self.__dict__
        if "registers" in d and name in d["registers"]: return d["registers"][name].read()
        if "arrays" in d and name in d["arrays"]: return d["arrays"][name]
        raise AttributeError(name)
    def __setattr__(self, name, value):
        regs = self.__dict__.get("registers")
        if regs is not None and name in regs: regs[name].write(value)
        else: object.__setattr__(self, name, value)
    def allocate(self, nbytes_or_shape, dtype=None): return _allocate(nbytes_or_shape, dtype)
    def irq(self): return UioIrq(self.meta.get("interrupt", "fabric"))
    def __dir__(self): return sorted(set(list(self.__dict__) + list(getattr(self, "registers", {})) + list(getattr(self, "arrays", {})) + ["allocate", "irq"]))
    def __repr__(self):
        rows = "\n".join("  %-12s %#06x  %-3s %s" % (r.name, r.offset, r.access, r.description) for r in self.registers.values())
        return "Overlay %s (%s)\n%s" % (self.name, os.path.basename(self.bitstream), rows)
