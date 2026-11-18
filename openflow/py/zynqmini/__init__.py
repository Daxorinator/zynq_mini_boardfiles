"""zynqmini: a small PYNQ-free hardware layer for the ZYNQ MINI (run on the board as root).
    from zynqmini import load_bitstream, MMIO, set_fclk, allocate, UioIrq
It replaces what the PL tests used PYNQ for: loading a bitstream, register access, FCLK, DMA-able buffers and PL interrupts."""
from .fpga import load_bitstream, bit_to_bin, fpga_state
from .mmio import MMIO
from .clocks import fclk_mhz, set_fclk, pll_mhz
from .buffer import allocate, Buffer
from .irq import UioIrq
from .mdio import Mdio
__all__ = ["load_bitstream", "bit_to_bin", "fpga_state", "MMIO", "fclk_mhz", "set_fclk", "pll_mhz", "allocate", "Buffer", "UioIrq", "Mdio"]
