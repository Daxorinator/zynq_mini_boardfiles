#!/bin/sh
# Build the host trace of the open init and compare with the Vivado-generated one.
set -e
cd "$(dirname "$0")"
python3 decode.py > /dev/null
python3 gen_ddr_table.py > /dev/null
gcc -Wall -Wextra -O1 -o trace_host trace_host.c ps7_open.c -DPS7_HOST_TRACE
python3 compare.py
