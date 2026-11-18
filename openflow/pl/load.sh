#!/usr/bin/env bash
# usage: load.sh <file.bin> [board-ip]    Loads a PL bitstream through the PYNQ image's Linux FPGA manager (default login xilinx/xilinx).
# Every design must instantiate PS7 (see README): a bitstream without it can freeze the PS when loaded this way.
IP=${2:-${BOARD_IP:-pynq}}; F=$1; N=$(basename "$F"); PW=${BOARD_PW:-xilinx}
sshpass -p "$PW" scp -o StrictHostKeyChecking=no "$F" xilinx@$IP:/tmp/
sshpass -p "$PW" ssh -o StrictHostKeyChecking=no xilinx@$IP "echo $PW | sudo -S sh -c 'cp /tmp/$N /lib/firmware/; echo 0 > /sys/class/fpga_manager/fpga0/flags; echo $N > /sys/class/fpga_manager/fpga0/firmware; cat /sys/class/fpga_manager/fpga0/state'"
