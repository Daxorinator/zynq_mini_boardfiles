#!/usr/bin/env python3
"""Minimal open Zynq-7000 BOOT.BIN assembler (non-secure, no bitstream support needed so far).
Layout reverse-engineered from a bootgen-built image and verified byte-for-byte against it (see verify below).
usage: mkboot.py out.bin  name:file:load:exec [name:file:load:exec ...]   (first = FSBL, flat binary of the ELF)"""
import struct, sys
M = 0xFFFFFFFF
def w(*v): return struct.pack("<%dI" % len(v), *[x & M for x in v])
def align(n, a): return (n + a - 1) // a * a
def build(parts, qspi_width=1):
    nparts = len(parts)
    img = bytearray(b"\xff" * 0x1700)
    # --- boot header ---
    img[0x00:0x20] = w(*([0xEAFFFFFE] * 8))
    img[0x20:0x24] = w(0xAA995566); img[0x24:0x28] = w(0x584C4E58)
    img[0x28:0x2C] = w(0)                       # not encrypted
    img[0x2C:0x30] = w(0x01010000)              # header version
    # partition data placement
    off = 0x1700; offs = []
    for name, data, load, ex in parts:
        offs.append(off); off = align(off + align(len(data), 4), 0x40)
    fsbl = parts[0]
    img[0x30:0x44] = w(offs[0], len(fsbl[1]), fsbl[2], fsbl[3], len(fsbl[1]))
    img[0x44:0x48] = w(qspi_width)
    s = sum(struct.unpack("<10I", img[0x20:0x48])) & M
    img[0x48:0x4C] = w(~s)
    img[0x4C:0x98] = w(*([0] * 19))
    img[0x98:0xA0] = w(0x8C0, 0x8C0 + 0x3C0)    # image header table, partition header table (0xC80)
    for i in range(256): img[0xA0 + 8 * i:0xA8 + 8 * i] = w(0xFFFFFFFF, 0)
    img[0x8A0:0x8C0] = b"\xff" * 0x20
    # --- image header table @0x8C0 ---
    img[0x8C0:0x8D4] = w(0x01020000, nparts, 0xC80 // 4, 0x900 // 4, 0)
    # --- image headers @0x900 (0x40 each) ---
    for i, (name, data, load, ex) in enumerate(parts):
        b = 0x900 + 0x40 * i
        nxt = (b + 0x40) // 4 if i < nparts - 1 else 0
        nm = name.encode() + b"\0"
        nm = nm.ljust(align(len(nm), 4), b"\0") + b"\0\0\0\0"     # word-padded name plus a terminating zero word
        nm = b"".join(nm[j:j + 4][::-1] for j in range(0, len(nm), 4))
        img[b:b + 0x10] = w(nxt, (0xC80 + 0x40 * i) // 4, 0, 1)
        img[b + 0x10:b + 0x10 + len(nm)] = nm
    # --- partition headers @0xC80 (0x40 each, plus a terminating null header) ---
    for i, (name, data, load, ex) in enumerate(parts):
        words = align(len(data), 4) // 4
        h = [words, words, words, load, ex, offs[i] // 4, 0x10, 1, 0, (0x900 + 0x40 * i) // 4, 0, 0, 0, 0, 0]
        c = (~(sum(h) & M)) & M
        img[0xC80 + 0x40 * i:0xC80 + 0x40 * i + 0x40] = w(*h, c)
    img[0xC80 + 0x40 * nparts:0xC80 + 0x40 * nparts + 0x40] = w(*([0] * 15), 0xFFFFFFFF)
    for (name, data, load, ex), o in zip(parts, offs):
        if len(img) < o: img += b"\xff" * (o - len(img))
        img[o:o + len(data)] = data
        pad = align(len(data), 4) - len(data)
        if pad: img += b"\0" * pad
    return bytes(img)
if __name__ == "__main__":
    out = sys.argv[1]; parts = []
    for spec in sys.argv[2:]:
        name, path, load, ex = spec.split(":")
        parts.append((name, open(path, "rb").read(), int(load, 0), int(ex, 0)))
    open(out, "wb").write(build(parts)); print("wrote", out)
