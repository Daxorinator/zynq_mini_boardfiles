# Overlays and PL tests

Everything here is built with Vivado 2024.1 through `../build.sh` and lands in `out/` (git-ignored). Copy the
`.bit`, `.hwh` (and `.dtbo` where listed) of an overlay to the board together, keeping the same base name.

| Overlay | Build | What it is | Status |
|---|---|---|---|
| `leds_keys` | `./build.sh overlay` | AXI GPIO on LED1..4 and KEY2/KEY3; `leds_keys_test.py` | verified on hardware |
| `pltest/` | `./build.sh pltest [jobs]` | One design that exercises the PL with no cable or add-on board: LEDs/keys, 34 header pins, PL clocks (frequency meter), timer interrupt, AXI DMA loopback, AT24C02 EEPROM, SSD1306 OLED, PL Ethernet PHY over MDIO. Runner: `pltest_run.py` | see below |
| `hdmi_test/` | `./build.sh hdmi [jobs]` | 640x480@60 Hz test pattern from a plain RTL TMDS transmitter (no licensed IP); `hdmi_test.py` | built only, **never run with a monitor** |

## `pltest`

On the board, as root, in the folder with `pltest.bit`, `.hwh`, `.dtbo` and `pltest_run.py`:

```
python3 pltest_run.py            # all tests; --list shows the names; or name some: clocks dma
```

| Test | What it checks | Needs |
|---|---|---|
| `leds_keys` | LED register write/readback (watch the chase on LED1..4), KEY2/KEY3 idle high | nothing |
| `header` | each of the 34 expansion header signals drives high and low, and no pin drags another (shorts) | **nothing plugged into the header** (pins have weak pull-downs; a pin that follows a driven neighbour is a short) |
| `clocks` | MMCM from the 50 MHz oscillator at 50/100/150/200 MHz, and PS FCLK1/FCLK2 over several settings, all measured against FCLK0 by an RTL frequency meter | nothing |
| `timer_irq` | 100 AXI Timer interrupts at 10 ms through the stock `fabric` UIO device (IRQ_F2P[0]: PL interrupt to GIC to user space), timing within 3 % | nothing |
| `dma` | AXI DMA MM2S looped to S2MM, 64 B to 4 MiB with and without interrupts, data compared, 64 KiB of guard bytes after the destination must stay untouched, transfer rate (about 375 to 400 MB/s) | `pltest.dtbo` for the interrupt part |
| `eeprom` | I2C bus idle high, scan for devices, read 16 bytes, write/read back 8 bytes at 0xF8 and restore them | nothing |
| `oled` | initialises the SSD1306 and draws a border, diagonals and "ZYNQ MINI PL OK" | **look at the screen**; the display cannot be read back |
| `ple_phy` | resets the PL Ethernet PHY and reads its ID over MDIO (Realtek RTL8211E expected), reports link state | nothing (no cable needed to read the ID) |
| `keys_live` | waits 10 s for you to press KEY2 and KEY3 | a human |

Not covered: the PL Ethernet data path (RGMII), which needs the licensed AXI Ethernet IP and a cable, and HDMI (see
above).

The runner talks to the AXI GPIOs through `/dev/mem` and to interrupts through `/dev/uio*`, so it does not depend on
PYNQ IP drivers other than `Overlay` (to load the bitstream and the device-tree overlay) and `allocate`/`Clocks`.

## Latest results (on the board, rebuilt image's PS clock fix applied)

`leds_keys` pass, `clocks` pass (MMCM 50/100/150/200 MHz and FCLK1/FCLK2 over 7 settings all within 0.001 %), `timer_irq`
pass (100 interrupts in 1.0001 s), `dma` pass (375 to 400 MB/s, no overrun), `eeprom` pass (AT24C02 at 0x50, blank, 8-byte
write/read back/restore), `ple_phy` pass (RTL8211E, ID 0x001C:0xC915, no link without a cable), `oled` pattern sent (look at
the screen), `header` pass (34 signals drive both ways, no coupling, with weak pull-downs).

## Things this work taught us (so they are not rediscovered)

* The board's PS clock is 33.333 MHz; stock PYNQ assumed 50 MHz (fixed in the image, see `../BUILDING.md`).
* The I2C bus has a pull-up on SDA (F20) but none on SCL (F19), so SCL is driven push-pull (fine with a single master).
* RTL8211E MDIO: read the turnaround as one clock (as Linux's `mdio-bitbang` does), otherwise the ID reads shifted left by a bit.
* Vivado's `apply_bd_automation` gives a second AXI master its own interconnect when the slave port is already taken; the
  DMA's S2MM write master ended up on an interconnect that went nowhere and the loopback hung. `build_pltest.tcl` builds
  one interconnect for both masters.
* The stock PYNQ device tree already owns IRQ_F2P[0] with a UIO node called `fabric`; the test uses it and `pltest.dtso` adds
  nodes only for IRQ_F2P[1..3].
* Registers must be accessed with single 32-bit stores. `struct.pack_into` on an mmap can use byte stores, and a byte write
  to a DMA LENGTH register starts a transfer with a garbage length, which overran buffers in memory.
* PYNQ's `ip_dict` reports a wrong base address for AXI GPIOs with an external tri-state interface; the runner reads
  addresses from the `.hwh`.
