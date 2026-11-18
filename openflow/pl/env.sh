# Source me: sets up the open-source FPGA toolchain for the XC7Z010 (openXC7 + oss-cad-suite).
# Layout expected under $OPENXC7_HOME (default ~/openxc7):
#   tc/             openXC7 release (nextpnr-xilinx, Project X-Ray database, chip database); tested: 2026-10-18
#   oss-cad-suite/  Yosys, openFPGALoader (tested: 2026-10-14)
# See ../README.md for where to download them.
export OPENXC7_HOME=${OPENXC7_HOME:-$HOME/openxc7}
export OXC7=$OPENXC7_HOME/tc
export PATH=$OPENXC7_HOME/oss-cad-suite/bin:$OXC7/bin:$PATH
export CHIPDB=$OXC7/share/nextpnr/himbaechel/xilinx/chipdb-xc7z010.bin
export PRJXRAY_DB=$OXC7/share/nextpnr/external/prjxray-db/zynq7
