#!/bin/sh
# run by Buildroot with the target directory as $1: install the zynqmini Python layer, tests and bitstream loader helpers
set -e
HERE=$(cd "$(dirname "$0")" && pwd); OF=$HERE/../..
T=$1/opt/zynqmini; mkdir -p "$T"
cp -r "$OF/py/zynqmini" "$T/"; cp -r "$OF/py/tests" "$T/"
find "$T" -name __pycache__ -prune -exec rm -rf {} +
for d in hp_dma ple_mac zm_base; do [ -f "$OF/pl/build/$d/$d.bin" ] && mkdir -p "$T/bitstreams" && cp "$OF/pl/build/$d/$d.bin" "$T/bitstreams/"; done
echo 'export PYTHONPATH=/opt/zynqmini:$PYTHONPATH' > "$1/etc/profile.d/zynqmini.sh"
# also make it importable from non-login shells (ssh commands, systemd services, Jupyter): a .pth file in site-packages
for sp in "$1"/usr/lib/python3*/site-packages; do [ -d "$sp" ] && echo /opt/zynqmini > "$sp/zynqmini.pth"; done
