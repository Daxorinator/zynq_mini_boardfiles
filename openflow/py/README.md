# zynqmini: a PYNQ-free hardware layer

Run on the board as root. `import zynqmini` gives: `load_bitstream` (FPGA manager, .bit or .bin), `MMIO` (registers through /dev/mem, real 32-bit accesses),
`set_fclk`/`fclk_mhz`/`pll_mhz` (PL clocks through the SLCR), `allocate` (contiguous uncached DMA buffers through the `zmbuf` driver, see `../linux`),
`UioIrq` (PL interrupt through UIO) and `Mdio` (PHY management bit-banged through a PL register block).
It needs the open kernel (`../linux`) for `allocate` (`zmbuf`); the other parts work on any kernel with /dev/mem and the FPGA manager.

PYNQ-style use: `Overlay("zm_base")` loads the bitstream and a JSON register map (`zynqmini/maps/*.json`; open-flow designs have no Vivado metadata) and exposes registers as attributes (`ol.LEDS = 5`, `ol.METER_100`),
`HpDma` drives the PL DMA, `allocate((n,), "uint32")` gives numpy-backed contiguous buffers. `pip install ./py` installs it (pyproject.toml); `notebooks/` has example notebooks; `python3 tests/test_overlay_offline.py` tests the layer without a board.

Tests (`python3 tests/<name>.py <bitstream.bin>`):
- `hp_dma_test.py ../pl/build/hp_dma/hp_dma.bin`: PL DMA through HP0 to 8 MiB, checksums, interrupt wakes a sleeping process. PASS on the open kernel.
- `pltest_open.py ../pl/build/zm_base/zm_base.bin`: the open-flow counterpart of the Vivado `pynq/overlay/pltest` overlay: LEDs and keys, clock meters (50/100/150/200 MHz
  and FCLK1/2 sweeps within 0.002 %), timer interrupt (100 in 1.0001 s), DMA copy through HP0 with interrupt, I2C EEPROM, OLED pattern, PHY id.
  PASS, all eight on the board (2026-11-18): including the header test (34 pins drive high and low, no coupling; the inputs idle through weak pull-ups, so the test waits 20 ms per
  step) and the OLED (needs a look: the pattern shows with the 0.35 s reset and settling the display wants; 10 ms was not enough). The header test drives the 34 header pins so it
  is opt-in (`--header`, unplug everything first).

Note: Linux keeps the SLCR unlocked at run time (its restart handler writes the reset register without unlocking). `set_fclk` therefore restores the previous lock state instead of always locking;
an earlier version re-locked it, which made `reboot` end with "Reboot failed -- System halted" until the next JTAG reset (fixed and checked 2026-11-18: after FCLK changes, `reboot` restarts the board).
