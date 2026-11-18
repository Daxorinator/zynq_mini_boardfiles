#!/usr/bin/env python3
"""Software side of the PL Ethernet MAC (ple_mac.bin loaded). Run on the board as root with the PYNQ venv:
    XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 ple_net.py selftest        # link, ARP to the peer, ping the peer
    XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 ple_net.py serve [seconds]  # answer ARP, ping and UDP echo (port 7)
The PS builds and parses all frames (including the FCS) and talks to the PL through registers over GP0; the PL does the RGMII timing.
Addresses: FPGA 10.0.0.2 (MAC 02:5a:59:4d:50:4c), peer (the laptop) 10.0.0.1."""
import mmap, os, struct, sys, time, zlib
from pynq import Clocks
from mdio import Mdio

MY_MAC = bytes.fromhex("025a594d504c"); MY_IP = bytes([10, 0, 0, 2]); PEER_IP = bytes([10, 0, 0, 1])
BCAST = b"\xff" * 6
Clocks.fclk0_mhz = 100
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x40000000)
rd = lambda o: int.from_bytes(m[o:o + 4], "little")
wr = lambda o, v: m.__setitem__(slice(o, o + 4), (v & 0xFFFFFFFF).to_bytes(4, "little"))
CTRL, STATUS, RXLEN, TXLEN, FRX, FTX, MISS = 0x24, 0x28, 0x2C, 0x30, 0x34, 0x38, 0x3C
RXBUF, TXBUF = 0x400, 0x200

def csum(b):
    if len(b) & 1: b += b"\0"
    s = sum(struct.unpack("!%dH" % (len(b) // 2), b))
    while s >> 16: s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF

def with_fcs(frame):
    frame = frame.ljust(60, b"\0")
    return frame + struct.pack("<I", zlib.crc32(frame) & 0xFFFFFFFF)

def eth(dst, src, typ, payload): return with_fcs(dst + src + struct.pack("!H", typ) + payload)

def arp(op, tha, tpa):
    return eth(BCAST if op == 1 else tha, MY_MAC, 0x0806,
               struct.pack("!HHBBH", 1, 0x0800, 6, 4, op) + MY_MAC + MY_IP + (b"\0" * 6 if op == 1 else tha) + tpa)

def ipv4(dst_ip, proto, payload, ident=0):
    h = struct.pack("!BBHHHBBH", 0x45, 0, 20 + len(payload), ident, 0x4000, 64, proto, 0) + MY_IP + dst_ip
    h = h[:10] + struct.pack("!H", csum(h)) + h[12:]
    return h + payload

def icmp(typ, ident, seq, data):
    b = struct.pack("!BBHHH", typ, 0, 0, ident, seq) + data
    return b[:2] + struct.pack("!H", csum(b)) + b[4:]

def send(frame, timeout=0.2):
    frame = frame if len(frame) >= 64 else with_fcs(frame[:-4])
    for i in range(0, len(frame), 4):
        wr(TXBUF + i, int.from_bytes(frame[i:i + 4].ljust(4, b"\0"), "little"))
    wr(TXLEN, len(frame)); wr(CTRL, 1)
    t0 = time.time()
    time.sleep(0.0005)
    while rd(STATUS) & 2:                                   # tx_busy
        if time.time() - t0 > timeout: raise RuntimeError("transmit did not finish")

def recv(timeout=0.2):
    """Return (frame_without_preamble, fcs_ok) or None."""
    t0 = time.time()
    while not (rd(STATUS) & 1):                              # rx_ready
        if time.time() - t0 > timeout: return None
    n = rd(RXLEN); raw = bytes(rd(RXBUF + 4 * i) & 0xFF for i in range(n))
    wr(CTRL, 2)                                              # release the buffer
    try: p = raw.index(b"\xd5") + 1                          # SFD; everything after it is the frame
    except ValueError: return None
    body = raw[p:]
    if len(body) < 18: return None
    ok = (zlib.crc32(body[:-4]) & 0xFFFFFFFF) == struct.unpack("<I", body[-4:])[0]
    return body, ok

def link_status():
    s = (rd(STATUS) >> 4) & 15
    return {"link": s & 1, "speed": (s >> 1) & 3, "duplex": (s >> 3) & 1}

def handle(frame, stats):
    dst, src, typ = frame[0:6], frame[6:12], struct.unpack("!H", frame[12:14])[0]
    pl = frame[14:-4]
    if typ == 0x0806 and len(pl) >= 28:
        op = struct.unpack("!H", pl[6:8])[0]; sha, spa, tpa = pl[8:14], pl[14:18], pl[24:28]
        if op == 1 and tpa == MY_IP:
            send(eth(sha, MY_MAC, 0x0806, struct.pack("!HHBBH", 1, 0x0800, 6, 4, 2) + MY_MAC + MY_IP + sha + spa)); stats["arp_replies"] += 1
        elif op == 2: stats["arp_in"] += 1; stats["peer"] = sha
    elif typ == 0x0800 and len(pl) >= 20 and pl[16:20] == MY_IP:
        ihl = (pl[0] & 15) * 4; proto = pl[9]; sip = pl[12:16]; body = pl[ihl:struct.unpack("!H", pl[2:4])[0]]
        if proto == 1 and body[0] == 8:
            ident, seq = struct.unpack("!HH", body[4:8])
            send(eth(src, MY_MAC, 0x0800, ipv4(sip, 1, icmp(0, ident, seq, body[8:]), ident))); stats["icmp_replies"] += 1
        elif proto == 1 and body[0] == 0: stats["icmp_in"] += 1
        elif proto == 17 and struct.unpack("!H", body[2:4])[0] == 7:
            sp, dp = struct.unpack("!HH", body[0:2]); data = body[8:struct.unpack("!H", body[4:6])[0]]
            udp = struct.pack("!HHHH", 7, sp, 8 + len(data), 0) + data
            send(eth(src, MY_MAC, 0x0800, ipv4(sip, 17, udp))); stats["udp_echo"] += 1

def serve(seconds):
    stats = {"rx": 0, "bad_fcs": 0, "arp_replies": 0, "arp_in": 0, "icmp_replies": 0, "icmp_in": 0, "udp_echo": 0}
    t_end = time.time() + seconds; last = 0
    while time.time() < t_end:
        r = recv(0.05)
        if r:
            frame, ok = r
            stats["rx"] += 1
            if not ok: stats["bad_fcs"] += 1
            else: handle(frame, stats)
        if time.time() - last > 1:
            last = time.time()
            open("/tmp/ple_net.stats", "w").write(" ".join("%s=%s" % (k, v) for k, v in stats.items() if k != "peer") + " hw_rx=%d hw_tx=%d missed=%d\n" % (rd(FRX), rd(FTX), rd(MISS)))
    return stats

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "selftest"
    md = Mdio(rd, wr); md.reset_phy()
    md.advertise_gigabit_only()
    t0 = time.time()
    while time.time() - t0 < 20:                             # auto-negotiation takes about 6 s
        bmsr = md.read(0, 1); bmsr = md.read(0, 1)            # the link bit latches low: read twice
        if bmsr & 4: break
        time.sleep(0.3)
    physr = md.read(0, 0x11)
    ls = {"link": (bmsr >> 2) & 1, "speed": (physr >> 14) & 3, "duplex": (physr >> 13) & 1, "rgmii_inband": link_status()}
    print("link", ls, "after %.1f s" % (time.time() - t0))
    wr(CTRL, 2 | 4); time.sleep(0.05)
    if mode == "serve":
        secs = float(sys.argv[2]) if len(sys.argv) > 2 else 60
        print("serving ARP/ping/UDP-echo on 10.0.0.2 for %.0f s" % secs); st = serve(secs); print(st); return
    ok = bool(ls["link"] and ls["speed"] == 2 and ls["duplex"])
    print("  %s  link up at 1000 Mb/s full duplex (PHYSR %#06x)" % ("ok  " if ok else "FAIL", physr))
    # ---- TX + RX: ARP request for the peer, wait for its reply
    peer_mac = None
    for attempt in range(5):
        send(arp(1, b"\0" * 6, PEER_IP)); t1 = time.time()
        while time.time() - t1 < 1.0 and peer_mac is None:
            r = recv(0.1)
            if not r: continue
            frame, fcs = r
            if fcs and frame[12:14] == b"\x08\x06" and struct.unpack("!H", frame[20:22])[0] == 2 and frame[28:32] == PEER_IP and frame[38:42] == MY_IP:
                peer_mac = frame[22:28]
        if peer_mac: break
    print("  %s  ARP reply from 10.0.0.1 (valid FCS): %s   [hw frames rx=%d tx=%d]" % ("ok  " if peer_mac else "FAIL", peer_mac.hex(":") if peer_mac else "none", rd(FRX), rd(FTX)))
    ok = ok and bool(peer_mac)
    # ---- ping the peer (informational: the laptop's firewall may drop echo requests)
    if peer_mac:
        got = 0
        for seq in range(4):
            send(eth(peer_mac, MY_MAC, 0x0800, ipv4(PEER_IP, 1, icmp(8, 0x4D41, seq, b"zynq-mini-pl-ethernet-ping-data"), seq))); t1 = time.time()
            while time.time() - t1 < 1.0:
                r = recv(0.1)
                if r and r[1] and r[0][12:14] == b"\x08\x00" and r[0][23] == 1 and r[0][34] == 0: got += 1; break
        print("  info  ICMP echo replies from the peer: %d of 4 (0 is normal if its firewall blocks ping)" % got)
    print("PL_ETH RESULT: %s" % ("PASS" if ok else "FAIL"))
    sys.exit(0 if ok else 1)
if __name__ == "__main__":
    main()
