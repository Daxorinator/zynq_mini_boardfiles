# ZYNQ MINI board files for Vivado

Vivado board files for the **ZYNQ MINI** (Zynq-7000 XC7Z010-1CLG400) development board, plus an English translation of its hardware specification.

With these installed you can pick the board when creating a Vivado project, and the Zynq PS7 block comes pre-configured for it: DDR3, QSPI, Ethernet, USB, both SD slots, UART and the clock. The board's LEDs, buttons and 50 MHz clock also appear as ready-made interfaces in IP Integrator.

| | |
|---|---|
| Board part | `bochenjingxin:zynq_mini:part0:1.0` |
| Device | `xc7z010clg400-1` |
| Board revision | REVB (silkscreen 20221015) |
| Tested with | Vivado 2024.1 |

## The board

The ZYNQ MINI is a small, low-cost Zynq-7010 board sold on Taobao by **Bochen Jingxin (博宸精芯)**, with teaching material published under the name **Little Panda Academy (小熊猫学堂)**. It has no English documentation and no official Vivado board files, which is why this repo exists. Two things are easy to trip over:

- **The DDR3 is 16-bit, not 32-bit.** There is a single 512 MB MT41J256M16 chip, so the PS DDR width must be set to 16 bit. The Vivado default is 32 bit and will not boot. The preset in this repo handles it.
- **The vendor's example projects are Vivado 2018.3.** Some of their constraint files contain stale pin assignments from a different, larger device (balls that do not exist on the CLG400 package), and one constrains an HDMI HPD pin that is wired to the OLED on this board. See Appendix E of the documentation before reusing them.

Highlights: 512 MB DDR3, 128 Mbit QSPI flash, two TF card slots (SD0 can boot), two RTL8211E gigabit Ethernet ports (one on the PS, one on the PL), USB 2.0 host via USB3320 ULPI, CH340 USB-UART, FT232H JTAG, HDMI output, 0.96" OLED, AT24C02 EEPROM, a 40-pin header with 34 IOs, and three Type-C connectors for JTAG, USB and UART.

## What the board files cover

| Interface | Details |
|---|---|
| `ps7_fixedio` (preset) | 33.333 MHz PS crystal; DDR3 MT41J256M16 RE-125, 16-bit, 533 MHz; QSPI on MIO 1-6; Ethernet 0 RGMII on MIO 16-27 with MDIO on MIO 52-53; USB0 ULPI on MIO 28-39 with reset on MIO 46; SD0 on MIO 40-45; SD1 on MIO 10-15; UART1 on MIO 48-49; MIO GPIO; bank voltages 3.3 V (bank 500) and 1.8 V (bank 501) |
| `sys_clock` | 50 MHz PL oscillator on K17 |
| `leds_4bits` | Four PL LEDs on T12, U12, V12, W13 (active high) |
| `push_buttons_2bits` | Two PL keys on M20 and M19 (active low) |

Not modelled as board interfaces, because Vivado has no standard interface type for them: the 40-pin expansion header, HDMI TMDS, the OLED, the EEPROM I²C bus and the PL-side Ethernet RGMII. Their pin assignments are in the documentation, ready to copy into an XDC.

## Installing

Pick one:

1. **Copy into Vivado.** Copy the `zynq_mini` folder (the one containing `1.0/`) into `<Vivado install>/data/boards/board_files/` and restart Vivado.
2. **Use a custom path.** Keep the folder anywhere and, in the Vivado Tcl console *before creating a project*:

   ```tcl
   set_param board.repoPaths [list /path/to/this/repo]
   ```

   To make that permanent, put the line in `~/.Xilinx/Vivado/Vivado_init.tcl` (`%APPDATA%\Xilinx\Vivado\Vivado_init.tcl` on Windows).

Check it loaded with `get_board_parts *zynq_mini*`, then choose **ZYNQ MINI Development Board** under **New Project → Boards**.

### Usage notes

- After adding the Zynq PS7 in IP Integrator, run **Run Block Automation** to apply the preset, then **Run Connection Automation** to wire the AXI GPIO blocks for the LEDs and buttons to the board interfaces.
- `sys_clock` has no Clocking Wizard preset. If you add a Clocking Wizard, set its input frequency to 50 MHz by hand.
- Boot mode is set by the BOOT switch: JTAG `00`, QSPI `10`, SD `11`.

## Documentation

[`docs/ZYNQ_MINI_Hardware_Specification_EN.pdf`](docs/ZYNQ_MINI_Hardware_Specification_EN.pdf) ([Markdown source](docs/ZYNQ_MINI_Hardware_Specification_EN.md)) is an English translation of the vendor's hardware specification, with the relevant schematic sections cropped in as figures. It covers power, clocks and boot, debug and UART, DDR3, both Ethernet ports, storage, the expansion header, LEDs and keys, USB, HDMI and the OLED, and ends with a complete pin summary and notes on the vendor's example projects.

## Where the information came from

Everything was derived from the vendor's package for the board:

- the hardware specification PDF (Chinese) and the REVB schematic and silkscreen drawings;
- the vendor's tutorial projects (Vivado 2018.3 / SDK) and their XDC constraint files, used to cross-check pin assignments and the PS configuration;
- the component datasheets bundled with the package.

Where the sources disagreed, the schematic and the board's silkscreen photo took priority; items that came from outside the specification text are marked **[verified]** or **[added]** in the documentation. The structure follows Xilinx's board file schema 2.1, modelled on the `ebaz4205` community board files.

## Status

Verified by script: the XML is well formed, every pin mapping resolves, interface index ranges line up, preset names exist, and all pin names and balls are unique. Peripheral part numbers were checked against datasheets.

Loaded in Vivado 2024.1: the board appears in the project wizard, the PS7 preset and the LED/button interfaces can be used in a block design, which validates, and a Vitis (2023.2) application builds and connects over JTAG.

Not yet verified: behaviour on other Vivado versions, and the remaining peripheral presets (Ethernet, USB, SD) on hardware. Issues and pull requests are welcome, especially from anyone with a different board revision.

## License

The board files and tooling are released under the [MIT License](LICENSE).

`docs/` is an unofficial translation of the vendor's documentation and includes figures cropped from their schematics. The original material remains the property of its authors (Bochen Jingxin / Little Panda Academy); it is included for reference and will be removed on request.

This project is not affiliated with or endorsed by the vendor, AMD or Xilinx.
