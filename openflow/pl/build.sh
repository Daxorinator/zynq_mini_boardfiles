#!/usr/bin/env bash
# usage: build.sh <project> [top]     e.g.  ./build.sh hdmi_640x480
# Builds pl/<project>/<top>.v + .xdc with Yosys + nextpnr-xilinx and writes build/<project>/<top>.bit and <top>.bin.
# The .bin is what the Linux FPGA manager on the board loads (header stripped, 32-bit words byte-swapped).
# Optional: SEED=<n> to change the nextpnr placer seed.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
P=$1; T=${2:-$1}; D=xc7z010clg400-1
[ -f "$HERE/$P/$T.v" ] || { echo "usage: $0 <project> [top]  (no $P/$T.v)"; exit 1; }
W=$HERE/build/$P; mkdir -p "$W"; cp -r "$HERE/$P"/. "$W"/; cd "$W"
yosys -q -p "read_verilog $T.v; synth_xilinx -flatten -abc9 -arch xc7 -top $T; write_json $T.json"
nextpnr-xilinx ${SEED:+--seed $SEED} --chipdb "$CHIPDB" --device $D --json $T.json --write ${T}_r.json \
    -o xdc=$T.xdc -o fasm=$T.fasm > $T.pnr.log 2>&1 || { tail -20 $T.pnr.log; exit 1; }
fasm2frames --part $D --db-root "$PRJXRAY_DB" $T.fasm $T.frames
xc7frames2bit --part_file "$PRJXRAY_DB/$D/part.yaml" --part_name $D --frm_file $T.frames --output_file $T.bit
python3 - "$T" <<'P'
import sys
t = sys.argv[1]; d = open(t + ".bit", "rb").read()
p = d.index(b'a\x00'); n = int.from_bytes(d[p+1:p+3], 'big'); p += 3 + n     # skip the .bit header fields
for k in b'bcd':
    n = int.from_bytes(d[p+1:p+3], 'big'); p += 3 + n
ln = int.from_bytes(d[p+1:p+5], 'big'); p += 5
b = d[p:p+ln]; s = bytearray(len(b))
for i in range(0, len(b), 4): s[i:i+4] = b[i:i+4][::-1]
open(t + ".bin", "wb").write(s)
P
grep -E "Max frequency" $T.pnr.log | tail -3
echo "built $W/$T.bin"
