# Bochen Jingxin ZYNQ MINI board files for Vivado

Vivado board files for the **Bochen Jingxin ZYNQ MINI REV B** (XC7Z010-1CLG400) development board, plus an English translation of its hardware specification.

With these installed you can pick the board when creating a Vivado project, and the Zynq PS7 block comes pre-configured for it: DDR3, QSPI, Ethernet, USB, both SD slots, UART and the clock. The board's LEDs, buttons and 50 MHz clock also appear as ready-made interfaces in IP Integrator.

| | |
|---|---|
| Board part | `bochenjingxin:zynq_mini:part0:1.0` |
| Device | `xc7z010clg400-1` |
| Board revision | REVB (silkscreen 20221015) |
| Tested with | Vivado 2024.1 |

## FPGA Board

The ZYNQ MINI is a small, low-cost Zynq-7010 board sold on AliExpress / Alibaba / Taobao by **Bochen Jingxin (博宸精芯)**, with teaching material published under the name **Little Panda Academy (小熊猫学堂)**. It has no English documentation and no official Vivado board files, which is why this repo exists.

Board specs:
- 512 MB DDR3
- 128 Mbit QSPI flash
- 2x TF card slots (SD0 can boot)
- 2x RTL8211E Gigabit Ethernet ports (PS + PL)
- Three Type-C connectors: USB 2.0 Host via USB3320 ULPI (USB Port), CH340 USB-UART (UART Port), FT232H JTAG (JTAG Port)
- HDMI Out
- 0.96" OLED via SPI + AT24C02 EEPROM via I2C
- 40-pin GPIO header with 34 IO pins

## What the board files cover

| Interface | Details |
|---|---|
| `ps7_fixedio` (preset) | 33.333 MHz PS crystal, 16-bit DDR3 @ 533 MHz, QSPI, ETH0 RGMII, USB0 ULPI, SD0 + SD1, UART1; MIO GPIO |
| `sys_clock` | 50 MHz PL Oscillator |
| `leds_4bits` | Four PL LEDs |
| `push_buttons_2bits` | Two PL keys |

Not modelled as board interfaces, because Vivado has no standard interface type for them:
- 40-pin expansion header
- HDMI TMDS
- OLED
- EEPROM
- PL-side Ethernet RGMII

Pin assignments for these devices are in the docs and have been tested in XDC.

## Installing
0. Download the repo
1. Copy the board files:
  - Copy the `zynq_mini` folder from the root of the project into `<Vivado>/data/boards/board_files/`
  - Restart Vivado.
2. Choose **ZYNQ MINI Development Board** under **New Project → Boards**.

### Usage notes

- After adding the Zynq PS7 in IP Integrator, run **Run Block Automation** to apply the preset, then **Run Connection Automation** to wire the AXI GPIO blocks for the LEDs and buttons to the board interfaces.
- `sys_clock` has no Clocking Wizard preset. If you add a Clocking Wizard, set its input frequency to 50 MHz by hand.
- Boot mode is set by the BOOT switch: JTAG `00`, QSPI `10`, SD `11`.

## Documentation

[`docs/ZYNQ_MINI_Hardware_Specification_EN.pdf`](docs/ZYNQ_MINI_Hardware_Specification_EN.pdf) ([Markdown source](docs/ZYNQ_MINI_Hardware_Specification_EN.md)) is an English translation of the vendor's hardware specification, with the relevant schematic sections cropped in as figures. It covers power, clocks and boot, debug and UART, DDR3, both Ethernet ports, storage, the expansion header, LEDs and keys, USB, HDMI and the OLED, and ends with a complete pin summary and notes on the vendor's example projects.

### Where the information came from

Everything was derived from the vendor's package for the board:

- the hardware specification PDF (Chinese) and the REVB schematic and silkscreen drawings;
- the vendor's tutorial projects (Vivado 2018.3 / SDK) and their XDC constraint files, used to cross-check pin assignments and the PS configuration;
- the component datasheets bundled with the package.

The vendor package for the board was sourced from a seller on AliExpress who provided a Baidu link, with the files kindly downloaded from Baidu in China by [@p0nch00](https://github.com/p0nch00)

## Status
Verified:
- Loads in Vivado 2024.1
- The board appears in the project wizard, the PS7 preset and the LED/button interfaces can be used in a block design, which validates OK, implementation and bitstream both OK
- A Vitis 2024.1 application utilising the bitstream from Vivado builds and connects over JTAG OK

Not Verified:
- Behaviour on other Vivado versions
- Remaining peripheral presets (Ethernet, USB, SD) on hardware
- Issues and pull requests are welcome, especially from anyone with a different board revision.

## License

The board files and tooling are released under the [MIT License](LICENSE).

`docs/` is an unofficial translation of the vendor's documentation and includes figures cropped from their schematics. The original material remains the property of its authors (Bochen Jingxin / Little Panda Academy); it is included for reference and will be removed on request.

This project is not affiliated with or endorsed by the vendor, AMD or Xilinx.
