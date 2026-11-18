#!/usr/bin/env bash
# builds build/out/qspi_flash.bin from an existing build (../build.sh): BOOT.BIN at 0 (bootgen-style header), u-boot.img at 0x100000
set -e
HERE=$(cd "$(dirname "$0")" && pwd); O=$HERE/../build/out
python3 "$HERE/../mkboot.py" "$O/BOOT_QSPI.bin" spl:"$O/spl/u-boot-spl.bin":0x0:0x0
python3 - "$O" <<'P'
import sys
o=sys.argv[1]; b=open(o+'/BOOT_QSPI.bin','rb').read(); u=open(o+'/u-boot.img','rb').read()
assert len(b)<=0x100000
img=bytearray(b"\xff"*(0x100000+len(u))); img[:len(b)]=b; img[0x100000:]=u
open(o+'/qspi_flash.bin','wb').write(img); print("qspi_flash.bin", len(img))
P
