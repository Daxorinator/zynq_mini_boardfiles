"""zynqmini: a small PYNQ-free hardware layer for the ZYNQ MINI (run on the board as root).
    from zynqmini import load_bitstream, MMIO, set_fclk, allocate, UioIrq
It covers what the PL tests used PYNQ for: loading a bitstream, register access, FCLK, DMA-able buffers and PL interrupts, plus PYNQ-style\noverlays (`Overlay("zm_base")` with registers as attributes, from a JSON map) and the HP-port DMA helper."""
from .fpga import load_bitstream, bit_to_bin, fpga_state
from .mmio import MMIO
from .clocks import fclk_mhz, set_fclk, pll_mhz
from .buffer import allocate, Buffer
from .irq import UioIrq
from .mdio import Mdio
from .overlay import Overlay, Register
from .hp_dma import HpDma, DmaError
__version__ = "0.2.0"
__all__ = ["Overlay", "Register", "HpDma", "DmaError", "load_bitstream", "bit_to_bin", "fpga_state", "MMIO", "fclk_mhz", "set_fclk", "pll_mhz", "allocate", "Buffer", "UioIrq", "Mdio"]
