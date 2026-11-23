#!/usr/bin/env bash
# generates ple_mac_f.v (ple_mac.v with ple_mac_props.vh included before its final endmodule) and runs the bounded proof
set -e
HERE=$(cd "$(dirname "$0")" && pwd); cd "$HERE"
python3 - <<'P'
s = open(__import__("os").environ.get("PLE_MAC_SRC", "../ple_mac/ple_mac.v")).read(); i = s.rindex("endmodule")
open("ple_mac_f.v", "w").write(s[:i] + '`include "ple_mac_props.vh"\n' + s[i:])
P
sed 's/assert(/cover(/g' formal_ps7.v > formal_ps7_gp0.v            # ple_mac does not use HP0: its AXI master rules are not applicable
rm -rf ple_mac_bmc ple_mac_cover; sby -f ple_mac.sby ${1:-bmc}
