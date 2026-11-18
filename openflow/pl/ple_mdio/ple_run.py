# PL Ethernet PHY (RTL8211E) management over MDIO, bit-banged from the PS through the open-flow AXI register block.
import mmap, os, ctypes, time
from pynq import Clocks
Clocks.fclk0_mhz = 100
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x40000000)
a = (ctypes.c_uint32 * 0x400).from_buffer(m)
rd = lambda o: a[o // 4]
def wr(o, v): a[o // 4] = v & 0xFFFFFFFF
print("ID %#x (want 0x4f584337)" % rd(0))
st = {"rst": 0, "mdc": 0, "rel": 1}
def put(): wr(0x1C, st["rst"] | (st["mdc"] << 1) | (st["rel"] << 2))
def clk(bit=None):
    if bit is None:            # read a bit: release MDIO, pulse MDC, sample while high
        st["rel"] = 1; st["mdc"] = 0; put(); st["mdc"] = 1; put(); v = rd(0x20) & 1; st["mdc"] = 0; put(); return v
    st["rel"] = bit; st["mdc"] = 0; put(); st["mdc"] = 1; put(); st["mdc"] = 0; put()
def read(phy, reg):
    for _ in range(32): clk(1)
    for b in (0, 1, 1, 0): clk(b)
    for i in range(4, -1, -1): clk((phy >> i) & 1)
    for i in range(4, -1, -1): clk((reg >> i) & 1)
    z = clk(None)
    v = 0
    for _ in range(16): v = (v << 1) | clk(None)
    return v, z == 0
st.update(rst=0, mdc=0, rel=1); put(); time.sleep(0.02)
st["rst"] = 1; put(); time.sleep(0.2)
print("MDIO idle level:", rd(0x20) & 1)
found = None
for phy in range(32):
    r2, ok = read(phy, 2)
    if ok and r2 not in (0, 0xFFFF):
        found = (phy, r2, read(phy, 3)[0]); break
if not found:
    print("FAIL: no PHY answered on MDIO"); raise SystemExit(1)
phy, r2, r3 = found
read(phy, 1); r1, _ = read(phy, 1); physr, _ = read(phy, 0x11)
print("PHY addr %d  ID %#06x:%#06x  (Realtek OUI 0x001c, RTL8211E model 0xc91x expected)" % (phy, r2, r3))
print("status %#06x -> %s ; PHYSR %#06x" % (r1, "LINK UP" if r1 & 4 else "no link", physr))
print("PASS" if r2 == 0x001C and (r3 >> 4) == 0xC91 else "UNEXPECTED ID")
