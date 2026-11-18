# zynqmini: a PYNQ-free hardware layer

Run on the board as root. `import zynqmini` gives: `load_bitstream` (FPGA manager, .bit or .bin), `MMIO` (registers through /dev/mem, real 32-bit accesses),
`set_fclk`/`fclk_mhz`/`pll_mhz` (PL clocks through the SLCR), `allocate` (contiguous uncached DMA buffers through the `zmbuf` driver, see `../linux`),
`UioIrq` (PL interrupt through UIO) and `Mdio` (PHY management bit-banged through a PL register block).
It needs the open kernel (`../linux`) for `allocate` (`zmbuf`); the other parts work on any kernel with /dev/mem and the FPGA manager.

Tests (`python3 tests/<name>.py <bitstream.bin>`):
- `hp_dma_test.py ../pl/build/hp_dma/hp_dma.bin`: PL DMA through HP0 to 8 MiB, checksums, interrupt wakes a sleeping process. PASS on the open kernel.
- `pltest_open.py ../pl/build/zm_base/zm_base.bin`: the open-flow counterpart of the Vivado `pynq/overlay/pltest` overlay: LEDs and keys, clock meters (50/100/150/200 MHz
  and FCLK1/2 sweeps within 0.002 %), timer interrupt (100 in 1.0001 s), DMA copy through HP0 with interrupt, I2C EEPROM, OLED pattern, PHY id.
  PASS except two that are not automatic: the OLED needs a look, and the header test drives the 34 header pins so it is opt-in (`--header`, unplug everything first).
