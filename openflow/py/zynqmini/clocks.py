"""PL clocks FCLK0..3 from the PS: read and set through the SLCR, no PYNQ needed."""
from .mmio import MMIO

PS_CLK_HZ = 33_333_333.0
_SLCR = None
def _slcr():
    global _SLCR
    if _SLCR is None: _SLCR = MMIO(0xF8000000, 0x1000)
    return _SLCR
PLL_CTRL = {0: 0x100, 1: 0x104, 2: 0x108}          # ARM, DDR, IO PLL

def pll_mhz(which):
    """0 = ARM PLL, 1 = DDR PLL, 2 = IO PLL (MHz); 0.0 if in reset/powered down."""
    c = _slcr()[PLL_CTRL[which]]
    if c & 3: return 0.0
    return PS_CLK_HZ * ((c >> 12) & 0x7F) / 1e6

def fclk_mhz(n):
    c = _slcr()[0x170 + 0x10 * n]
    src = (c >> 4) & 3; d0 = (c >> 8) & 0x3F; d1 = (c >> 20) & 0x3F
    pll = pll_mhz({0: 2, 1: 2, 2: 0, 3: 1}[src])
    return pll / (d0 * d1) if d0 and d1 else 0.0

def set_fclk(n, mhz):
    """Set FCLKn to the closest achievable frequency from the IO PLL (divisors 1..63 each); returns the MHz actually set."""
    pll = pll_mhz(2); best = None
    for d0 in range(1, 64):
        for d1 in range(1, 64):
            f = pll / (d0 * d1)
            if best is None or abs(f - mhz) < abs(best[0] - mhz): best = (f, d0, d1)
    f, d0, d1 = best
    s = _slcr(); reg = 0x170 + 0x10 * n
    was_locked = s[0x00C] & 1                         # SLCR_LOCKSTA: Linux keeps the SLCR unlocked (its restart handler needs that), so only re-lock if it was locked
    s[0x008] = 0xDF0D                                # unlock the SLCR
    s[reg] = (s[reg] & ~((0x3 << 4) | (0x3F << 8) | (0x3F << 20))) | (d0 << 8) | (d1 << 20)   # source 0 = IO PLL
    if was_locked: s[0x004] = 0x767B                 # restore the previous lock state
    return fclk_mhz(n)
