import mmap, os, ctypes, time, sys
from pynq import Clocks
Clocks.fclk0_mhz = 100
print("FCLK0 set ->", Clocks.fclk0_mhz)
BASE = 0x40000000
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=BASE)
arr = (ctypes.c_uint32 * 0x400).from_buffer(m)
rd = lambda o: arr[o // 4]
def wr(o, v): arr[o // 4] = v & 0xFFFFFFFF
print("ID      %#010x (want 0x4f584337)" % rd(0))
wr(4, 0xA5A5F00F); print("scratch %#010x (want 0xa5a5f00f)" % rd(4))
c1 = rd(8); time.sleep(0.1); c2 = rd(8)
print("FCLK0 counter rate: %.2f MHz (100 expected)" % ((c2 - c1) / 0.1 / 1e6))
print("FCLK0 per 10.486 ms window: %d -> %.2f MHz" % (rd(0x18), rd(0x18) / 0.010486))
for p in (1, 2, 4, 8, 0xF, 0):
    wr(0x0C, p); assert rd(0x0C) == p; time.sleep(0.15)
print("keys    %#x (3 = none pressed)" % rd(0x10))
# I2C bit-bang (SCL push-pull, SDA open drain), AT24C02 at 0x50
def setp(scl, sda): wr(0x14, scl | (sda << 1)); time.sleep(0.00002)
def sda(): return (rd(0x14) >> 1) & 1
def start(): setp(1,1); setp(1,0); setp(0,0)
def stop(): setp(0,0); setp(1,0); setp(1,1)
def wbyte(b):
    for i in range(7,-1,-1):
        bit=(b>>i)&1; setp(0,bit); setp(1,bit); setp(0,bit)
    setp(0,1); setp(1,1); a = sda()==0; setp(0,1); return a
def rbyte(ack):
    v=0; setp(0,1)
    for _ in range(8):
        setp(1,1); v=(v<<1)|sda(); setp(0,1)
    n = 0 if ack else 1
    setp(0,n); setp(1,n); setp(0,n); setp(0,1); return v
setp(1,1)
print("SDA idle level:", sda())
found=[]
for a in range(0x08,0x78):
    start(); ok=wbyte(a<<1); stop()
    if ok: found.append(a)
print("I2C devices:", [hex(a) for a in found])
if 0x50 in found:
    start(); wbyte(0xA0); wbyte(0x00); start(); wbyte(0xA1)
    data=[rbyte(i<15) for i in range(16)]; stop()
    print("EEPROM 0x00..0x0F:", " ".join("%02x"%b for b in data))
def eread(off, n):
    start(); assert wbyte(0xA0) and wbyte(off); start(); assert wbyte(0xA1)
    d=[rbyte(i<n-1) for i in range(n)]; stop(); return d
def ewrite(off, data):
    start(); assert wbyte(0xA0) and wbyte(off)
    for b in data: assert wbyte(b)
    stop(); time.sleep(0.02)
saved = eread(0xF8, 8); pat=[0xA5,0x5A,0x3C,0xC3,0x01,0xFE,0x80,0x7F]
try:
    ewrite(0xF8, pat); got = eread(0xF8, 8)
finally:
    ewrite(0xF8, saved)
print("EEPROM write/readback:", "OK" if got==pat else "MISMATCH %s"%got, "| restored:", "OK" if eread(0xF8,8)==saved else "FAILED")
