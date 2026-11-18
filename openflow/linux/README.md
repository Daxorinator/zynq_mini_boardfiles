# Open Linux for the ZYNQ MINI

Kernel, device tree and boot files built from source with no Vivado, PetaLinux or PYNQ build system involved.

- `build.sh`  fetches the Xilinx `linux-xlnx` tag `xilinx-v2024.1` (SHA-256 pinned), builds `zImage`, the modules, the device tree and the
  `zmbuf` driver with `zynqmini_defconfig`: output in `build/out` (`zImage`, `zynq-zynqmini.dtb`, `modules.tgz`, `zmbuf.ko`).
  `zynqmini_defconfig` is the configuration of the PYNQ image's kernel plus `DMABUF_HEAPS`/`UDMABUF` and the version suffix `-zynqmini-open`.
- `dts/zynq-zynqmini.dts`  hand-written from the board specification on top of the kernel's own `zynq-7000.dtsi` (memory, aliases, PS Ethernet PHY
  on MIO16-27, both SD slots, QSPI flash partitions, UART1 console, USB ULPI PHY with its reset GPIO, role switch, UIO node for IRQ_F2P[0]).
  Checked against the device tree of the PYNQ image running on the board: the only differences are the PYNQ-only `xlnk` and `zyxclmm_drm`
  nodes (they serve Xilinx's out-of-tree drivers), the kernel's `ocm-sram` child, and the boot arguments.
- `zmbuf/`  a small kernel driver, `/dev/zmbuf`: physically contiguous, uncached DMA buffers for PL masters (what `xlnk` did). Without it a PL
  master is not cache-coherent with buffers allocated through dma-buf heaps (those only do cache maintenance for attached kernel devices).
- `mkimage.py`  assembles an SD image rootless: copies a base PYNQ image, replaces partition 1 with a new FAT32 volume (`BOOT.BIN`, `u-boot.img`,
  a boot script, `zImage`, the device tree) and adds the new modules and a `zmbuf` load entry to the root filesystem with `debugfs`.
  The root filesystem itself is the existing PYNQ/Ubuntu userland (open software, not rebuilt here); what is replaced is everything PetaLinux built.

Verified: the kernel and device tree boot on the board (`Linux 6.6.0-zynqmini-open`, started with U-Boot's `bootz` from a self-deleting `uEnv.txt`),
`/dev/dma_heap`, `/dev/uio0` and `zmbuf` work and the PL DMA tests pass on it (`../py/tests`). `build.sh` was run from a clean checkout and gives the
same `zImage` size and a byte-identical device tree. `mkimage.py` output was checked offline: partition table, `fsck.fat` clean, file contents equal
to their sources, `e2fsck` clean, new modules present. The generated boot script was verified on the board as a one-shot `uEnv.txt` (loads `zmboot.scr` from the FAT partition, which loads `zimage` and
`zynqmini.dtb` and runs `bootz`): the board came up on `6.6.0-zynqmini-open` with `/dev/zmbuf` created by the `modules-load.d` entry. The boot partition written by `mkimage.py` was also read back by U-Boot's own FAT driver (the U-Boot sandbox build, `host bind` + `fatls`/`fatload`/`md5sum`
from the same source tree as the board's U-Boot): all five files list and every checksum matches its source; the board's Linux also loop-mounts it and reads the same bytes.
NOT verified: powering up from a physical SD card written with `mkimage.py` (the boot ROM reading `BOOT.BIN` from it; needs a spare card swapped in, the board's second slot holds
a card with other data, which this work did not touch). Load the one-shot script away from the running script's own memory (`0x04000000`).
Not carried over from PYNQ: the Xilinx `zocl` (XRT) and `xlnk` drivers, so PYNQ's own Python library does not work on this kernel; use `../py/zynqmini`.
