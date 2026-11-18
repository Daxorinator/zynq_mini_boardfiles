#!/usr/bin/env python3
"""Offline test of the software protocol stack in ple_net.py (no board needed): crafted ARP/ICMP/UDP frames in, replies checked
for correct addresses, checksums and FCS. Run: python3 test_protocol.py"""
import os, struct, sys, zlib
os.environ["PLE_NET_NOHW"] = "1"
sys.argv = ["x", "none"]
import ple_net as n

sent = []
n.send = lambda f, timeout=0.2: sent.append(bytes(f))
PEER_MAC = bytes.fromhex("08bfb8e1fb03")
stats = {"rx": 0, "bad_fcs": 0, "arp_replies": 0, "arp_in": 0, "icmp_replies": 0, "icmp_in": 0, "udp_echo": 0}
ok = True
def check(c, m):
    global ok; ok &= bool(c); print(("ok   " if c else "FAIL ") + m)
def fcs_ok(f): return (zlib.crc32(f[:-4]) & 0xFFFFFFFF) == struct.unpack("<I", f[-4:])[0]
def peer_frame(typ, payload, dst=n.MY_MAC): return n.with_fcs(dst + PEER_MAC + struct.pack("!H", typ) + payload)
def peer_ip(proto, payload, ident=7):
    h = struct.pack("!BBHHHBBH", 0x45, 0, 20 + len(payload), ident, 0x4000, 64, proto, 0) + n.PEER_IP + n.MY_IP
    return h[:10] + struct.pack("!H", n.csum(h)) + h[12:] + payload

# ARP request for 10.0.0.2 -> ARP reply to the sender
req = peer_frame(0x0806, struct.pack("!HHBBH", 1, 0x0800, 6, 4, 1) + PEER_MAC + n.PEER_IP + b"\0" * 6 + n.MY_IP, dst=b"\xff" * 6)
n.handle(req, stats); r = sent.pop()
check(fcs_ok(r) and r[0:6] == PEER_MAC and r[6:12] == n.MY_MAC and r[12:14] == b"\x08\x06", "ARP reply: addressed to the requester, valid FCS")
check(struct.unpack("!H", r[20:22])[0] == 2 and r[22:28] == n.MY_MAC and r[28:32] == n.MY_IP and r[32:38] == PEER_MAC and r[38:42] == n.PEER_IP, "ARP reply: opcode 2, sender 10.0.0.2 / our MAC, target the requester")
# ARP request for another address is ignored
other = peer_frame(0x0806, struct.pack("!HHBBH", 1, 0x0800, 6, 4, 1) + PEER_MAC + n.PEER_IP + b"\0" * 6 + bytes([10, 0, 0, 99]), dst=b"\xff" * 6)
n.handle(other, stats); check(not sent, "ARP request for another IP is ignored")
# ICMP echo request -> echo reply with the same id/seq/data and valid checksums
data = bytes(range(32)); icmp_req = struct.pack("!BBHHH", 8, 0, 0, 0x1234, 5) + data
icmp_req = icmp_req[:2] + struct.pack("!H", n.csum(icmp_req)) + icmp_req[4:]
n.handle(peer_frame(0x0800, peer_ip(1, icmp_req)), stats); r = sent.pop(); ip = r[14:-4]
check(fcs_ok(r) and r[0:6] == PEER_MAC and ip[12:16] == n.MY_IP and ip[16:20] == n.PEER_IP and ip[9] == 1, "ICMP reply: addresses swapped, valid FCS")
check(n.csum(ip[:20]) == 0, "ICMP reply: IPv4 header checksum valid")
body = ip[20:20 + struct.unpack("!H", ip[2:4])[0] - 20]
check(body[0] == 0 and n.csum(body) == 0 and body[4:8] == icmp_req[4:8] and body[8:] == data, "ICMP reply: type 0, checksum valid, id/seq/data echoed")
# UDP echo on port 7
udp = struct.pack("!HHHH", 40000, 7, 8 + 10, 0) + b"hello zynq"
n.handle(peer_frame(0x0800, peer_ip(17, udp)), stats); r = sent.pop(); ip = r[14:-4]
check(fcs_ok(r) and n.csum(ip[:20]) == 0 and ip[9] == 17, "UDP echo: valid FCS and IPv4 checksum")
check(struct.unpack("!HHH", ip[20:26]) == (7, 40000, 18) and ip[28:38] == b"hello zynq", "UDP echo: ports swapped, payload echoed")
# a UDP packet to another port is ignored; a corrupted FCS is not accepted by recv's check
n.handle(peer_frame(0x0800, peer_ip(17, struct.pack("!HHHH", 40000, 9, 12, 0) + b"abcd")), stats); check(not sent, "UDP to a port other than 7 is ignored")
print("PROTOCOL TEST: %s" % ("PASS" if ok else "FAIL")); sys.exit(0 if ok else 1)
