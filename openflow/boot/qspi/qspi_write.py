#!/usr/bin/env python3
"""Write an image to the start of /dev/mtd0 (erase, write, read back, compare). Run as root on the board."""
import fcntl, os, struct, sys, hashlib
MEMERASE = 0x40084D02; BLK = 0x10000
img = open(sys.argv[1], "rb").read(); n = (len(img) + BLK - 1) // BLK * BLK
fd = os.open("/dev/mtd0", os.O_RDWR)
for off in range(0, n, BLK):
    fcntl.ioctl(fd, MEMERASE, struct.pack("II", off, BLK))
print("erased %d bytes" % n)
os.lseek(fd, 0, 0)
done = 0
while done < len(img):
    done += os.write(fd, img[done:done + 0x10000])
os.lseek(fd, 0, 0)
back = b""
while len(back) < len(img):
    c = os.read(fd, 0x10000)
    if not c: break
    back += c
back = back[:len(img)]
print("wrote %d bytes; readback %s (md5 %s)" % (len(img), "MATCHES" if back == img else "DIFFERS", hashlib.md5(back).hexdigest()))
sys.exit(0 if back == img else 1)
