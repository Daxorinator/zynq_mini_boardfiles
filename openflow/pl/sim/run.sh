#!/usr/bin/env bash
# Runs the RTL simulations (iverilog, from oss-cad-suite). usage: ./run.sh [testbench ...]   (default: all)
set -e
HERE=$(cd "$(dirname "$0")" && pwd); PL=$HERE/..
. "$PL/env.sh" 2>/dev/null || true
IVL=$(command -v iverilog || echo "${OPENXC7_HOME:-$HOME/openxc7}/oss-cad-suite/bin/iverilog"); VVP=$(command -v vvp || echo "$(dirname "$IVL")/vvp")
mkdir -p "$HERE/build"
declare -A SRC=( [zm_base]="$PL/zm_base/zm_base.v" [hp_dma]="$PL/hp_dma/hp_dma.v" )
want=${@:-zm_base hp_dma}; rc=0
for t in $want; do
  "$IVL" -g2012 -o "$HERE/build/tb_$t.vvp" "$HERE/models.v" "${SRC[$t]}" "$HERE/tb_$t.v"
  out=$("$VVP" -n "$HERE/build/tb_$t.vvp" | tail -15); echo "$out"; echo "$out" | grep -q "PASS" || rc=1
done
exit $rc
