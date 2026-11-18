# PL Ethernet RGMII loopback (PHY digital loopback via MDIO), open-flow design ple_rgmii
import mmap, os, ctypes, time, sys
from pynq import Clocks
Clocks.fclk0_mhz = 100
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x40000000)
a = (ctypes.c_uint32 * 0x400).from_buffer(m)
rd = lambda o: a[o // 4]
def wr(o, v): a[o // 4] = v & 0xFFFFFFFF
print("ID %#x (want 0x4d494931 'MII1'), MMCM locked=%d" % (rd(0), rd(0x2C) & 1))
st = {"rst": 0, "mdc": 0, "rel": 1}
def put(): wr(0x1C, st["rst"] | (st["mdc"] << 1) | (st["rel"] << 2))
def clk(bit=None):
    if bit is None:
        st["rel"] = 1; st["mdc"] = 0; put(); st["mdc"] = 1; put(); v = rd(0x20) & 1; st["mdc"] = 0; put(); return v
    st["rel"] = bit; st["mdc"] = 0; put(); st["mdc"] = 1; put(); st["mdc"] = 0; put()
def bits(v, n):
    for i in range(n - 1, -1, -1): clk((v >> i) & 1)
def mread(phy, reg):
    bits(0xFFFFFFFF, 32); bits(0b0110, 4); bits(phy, 5); bits(reg, 5)
    z = clk(None); v = 0
    for _ in range(16): v = (v << 1) | clk(None)
    return v
def mwrite(phy, reg, val):
    bits(0xFFFFFFFF, 32); bits(0b0101, 4); bits(phy, 5); bits(reg, 5); bits(0b10, 2); bits(val, 16)
    st["rel"] = 1; put()
PHY = int(sys.argv[1]) if len(sys.argv) > 1 else 0
st.update(rst=0, mdc=0, rel=1); put(); time.sleep(0.02); st["rst"] = 1; put(); time.sleep(0.3)
print("PHY ID @%d: %#06x:%#06x ; @1: %#06x" % (PHY, mread(PHY, 2), mread(PHY, 3), mread(1, 2)))
print("BMCR before: %#06x" % mread(PHY, 0))
def run(label, bmcr):
    mwrite(PHY, 0, bmcr); time.sleep(0.3)
    print("[%s] BMCR now %#06x" % (label, mread(PHY, 0)))
    wr(0x24, 0); time.sleep(0.01)
    wr(0x28, 60)                               # payload length
    wr(0x24, 2); time.sleep(0.01)              # arm RX capture
    wr(0x24, 3); time.sleep(0.01)              # go (keeps arm)
    time.sleep(0.2)
    wr(0x24, 2)
    done = (rd(0x2C) >> 1) & 1
    print("  rx clk count %d, dv count %d, capture done %d" % (rd(0x30), rd(0x34), done))
    raw = b"".join(rd(0x40 + 4 * i).to_bytes(4, "little") for i in range(20))
    print("  captured:", raw[:40].hex(" "))
    return raw
def analyse(raw):
    nib = []
    for b in raw: nib += [b & 15, b >> 4]
    best = None
    for p in range(len(nib) - 4):
        if nib[p] == 5 and nib[p + 1] == 0xD:
            pay = [nib[p + 2 + 2 * j] | (nib[p + 3 + 2 * j] << 4) for j in range(min(60, (len(nib) - p - 3) // 2))]
            ok = sum(1 for j, v in enumerate(pay) if v == j)
            bit_err = sum(bin(v ^ j).count("1") for j, v in enumerate(pay))
            if best is None or ok > best[0]: best = (ok, bit_err, p, pay)
    return best
raw = run("loopback 1000M", 0x4140)
best = analyse(raw)
if best is None: print("  RESULT: no SFD (5,D nibbles) found")
else:
    ok, be, p, pay = best
    print("  RESULT: SFD at nibble %d, %d/60 payload bytes exact, %d bit errors; first bytes %s" % (p, ok, be, bytes(pay[:12]).hex(" ")))
    print("  PASS" if ok == 60 else "  FAIL")
mwrite(PHY, 0, 0x1140)
