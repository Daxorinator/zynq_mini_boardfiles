#!/usr/bin/env bash
# Runs the bare-metal 511 MiB DDR test on the board and reports the verdict. No console capture or fixed timers needed:
# 1. copies ddrtest.bin and a one-shot /boot/uEnv.txt to the SD card (U-Boot runs the test on the next boot, deletes uEnv.txt
#    first, and arms the PS watchdog so a hang falls back to a normal boot),
# 2. reboots and waits until Linux is back with a NEW boot id (the test runs before Linux starts),
# 3. reads the result code the test left in SLCR REBOOT_STATUS[23:16]: 0xA5 pass, 0xE1 memory error, 0xE2 init failure,
#    0x00 = the test never completed (hang -> watchdog reset).
# usage: run_ddr_test.sh [board-ip]      env: BOARD_PW (default xilinx)
set -e
IP=${1:-${BOARD_IP:-pynq}}; PW=${BOARD_PW:-xilinx}; HERE=$(cd "$(dirname "$0")" && pwd)
BIN=$HERE/../boot/baremetal/build/ddrtest.bin
[ -f "$BIN" ] || { echo "build it first: boot/baremetal/build.sh"; exit 1; }
SSH="sshpass -p $PW ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 xilinx@$IP"
SCP="sshpass -p $PW scp -q -o StrictHostKeyChecking=no"
cat > /tmp/ddr_uEnv.txt <<'U'
zmw=mw.l 0xF8000008 0xDF0D; mw.l 0xF8000258 0; mw.l 0xF8005004 0x00923FFE; mw.l 0xF8005000 0x00ABC033; mw.l 0xF8005008 0x1999
zmc=dcache off; cp.b 0x01000000 0xFFFC0000 0x4000
uenvcmd=fatload ${devtype} ${devnum}:${distro_bootpart} 0x01000000 ddrtest.bin; fatrm ${devtype} ${devnum}:${distro_bootpart} uEnv.txt; run zmc; run zmw; go 0xFFFC0000
U
cat > /tmp/read_status.py <<'P'
import mmap, os, struct
fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ, offset=0xF8000000)
print("%#x" % struct.unpack("<I", m[0x258:0x25C])[0])
P
OLD=$($SSH 'cat /proc/sys/kernel/random/boot_id')
$SCP "$BIN" xilinx@$IP:/tmp/ddrtest.bin; $SCP /tmp/ddr_uEnv.txt /tmp/read_status.py xilinx@$IP:/tmp/
$SSH "echo $PW | sudo -S sh -c 'cp /tmp/ddrtest.bin /boot/ && cp /tmp/ddr_uEnv.txt /boot/uEnv.txt && sync && reboot'" >/dev/null 2>&1 || true
echo "rebooted at $(date +%T); waiting for a new boot id ..."
for i in $(seq 1 120); do
  NEW=$($SSH 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null || true)
  [ -n "$NEW" ] && [ "$NEW" != "$OLD" ] && break
  sleep 4
done
[ -n "$NEW" ] && [ "$NEW" != "$OLD" ] || { echo "board did not come back"; exit 2; }
sleep 3
$SCP /tmp/read_status.py xilinx@$IP:/tmp/ 2>/dev/null || true
ST=$($SSH "echo $PW | sudo -S /usr/local/share/pynq-venv/bin/python3 /tmp/read_status.py 2>/dev/null | tail -1")
$SSH "echo $PW | sudo -S rm -f /boot/ddrtest.bin /boot/uEnv.txt" >/dev/null 2>&1 || true
BYTE=$(( (ST >> 16) & 0xF7 ))
case $BYTE in
  165) echo "DDR TEST PASS  (REBOOT_STATUS=$ST, back up at $(date +%T))"; exit 0;;
  225) echo "DDR TEST FAIL: memory errors (REBOOT_STATUS=$ST)"; exit 1;;
  226) echo "DDR TEST FAIL: ps7 init failed (REBOOT_STATUS=$ST)"; exit 1;;
  *)   echo "DDR TEST DID NOT COMPLETE (REBOOT_STATUS=$ST): hang or never started"; exit 1;;
esac
