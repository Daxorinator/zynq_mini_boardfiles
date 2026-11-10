#!/bin/bash
# Check the second TF slot (SD1, MIO10-15, 3.3 V, not boot-capable). 
# Put a FAT/ext4-formatted card in the SD1/TF2 slot for testing.
#
# Run as root: sudo bash sd1_test.sh
set -u
echo "== MMC devices (SD0 boot card is mmcblk0; SD1 should appear as mmcblk1) =="
ls -l /dev/mmcblk* 2>&1
echo "== dmesg =="
dmesg | grep -i -E "mmc[0-9]|sdhci" | tail -15
DEV=/dev/mmcblk1p1
[ -b "$DEV" ] || DEV=/dev/mmcblk1
[ -b "$DEV" ] || { echo "No /dev/mmcblk1 - card not detected (reseat it; slots are easy to mix up)"; exit 1; }
echo "== read speed (100 MB from $DEV) =="
dd if="$DEV" of=/dev/null bs=1M count=100 2>&1 | tail -1
echo "== mount, write, read back =="
mkdir -p /mnt/sd1 && mount "$DEV" /mnt/sd1 || { echo "mount failed (unformatted card?)"; exit 1; }
echo "zynq-mini sd1 test $(date)" > /mnt/sd1/zm_sd1_test.txt && sync
cat /mnt/sd1/zm_sd1_test.txt && rm /mnt/sd1/zm_sd1_test.txt
df -h /mnt/sd1 | tail -1
umount /mnt/sd1 && echo "SD1 OK"
