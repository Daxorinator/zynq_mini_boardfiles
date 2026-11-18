"""Load a PL bitstream through the Linux FPGA manager (/sys/class/fpga_manager/fpga0)."""
import os, time

MGR = "/sys/class/fpga_manager/fpga0"

def bit_to_bin(data):
    """Vivado/openXC7 .bit -> raw .bin as the FPGA manager wants it: strip the header, swap the bytes of every 32-bit word."""
    p = data.index(b"a\x00")
    n = int.from_bytes(data[p + 1:p + 3], "big"); p += 3 + n        # design name field
    for _ in b"bcd":                                               # part, date, time
        n = int.from_bytes(data[p + 1:p + 3], "big"); p += 3 + n
    ln = int.from_bytes(data[p + 1:p + 5], "big"); p += 5          # 'e' field: bitstream length
    body = data[p:p + ln]
    out = bytearray(len(body))
    for i in range(0, len(body), 4):
        out[i:i + 4] = body[i:i + 4][::-1]
    return bytes(out)

def fpga_state():
    return open(MGR + "/state").read().strip()

def load_bitstream(path, name=None):
    """Load .bit or .bin (as built by openflow/pl/build.sh). Every design must instantiate PS7 (see openflow/README.md).
    Returns the manager state ('operating' on success)."""
    data = open(path, "rb").read()
    if data[:2] == b"\x00\x09":                                     # a .bit file (header starts 00 09 0f f0 ...)
        data = bit_to_bin(data)
    name = name or "zm_" + os.path.basename(path).rsplit(".", 1)[0] + ".bin"
    os.makedirs("/lib/firmware", exist_ok=True)           # minimal root filesystems (e.g. Buildroot) do not have it
    with open("/lib/firmware/" + name, "wb") as f: f.write(data)
    open(MGR + "/flags", "w").write("0")                            # full reconfiguration
    open(MGR + "/firmware", "w").write(name)
    for _ in range(50):
        st = fpga_state()
        if st == "operating": return st
        time.sleep(0.05)
    raise RuntimeError("FPGA manager state after loading %s: %s" % (name, st))
