"""MDIO bit-banging helpers for the PL Ethernet PHY (RTL8211E-VB) through the open-flow register blocks
(ple_mdio / ple_mac): register 0x1C = {mdio_release, mdc, reset_n}, 0x20 = MDIO pin level. Import after mapping GP0 as `rd`/`wr`."""
import time

class Mdio:
    def __init__(self, rd, wr, reg_ctl=0x1C, reg_pin=0x20):
        self.rd, self.wr, self.ctl, self.pin = rd, wr, reg_ctl, reg_pin
        self.st = {"rst": 0, "mdc": 0, "rel": 1}
    def _put(self): self.wr(self.ctl, self.st["rst"] | (self.st["mdc"] << 1) | (self.st["rel"] << 2))
    def _clk(self, bit=None):
        if bit is None:
            self.st["rel"] = 1; self.st["mdc"] = 0; self._put(); self.st["mdc"] = 1; self._put()
            v = self.rd(self.pin) & 1; self.st["mdc"] = 0; self._put(); return v
        self.st["rel"] = bit; self.st["mdc"] = 0; self._put(); self.st["mdc"] = 1; self._put(); self.st["mdc"] = 0; self._put()
    def _bits(self, v, n):
        for i in range(n - 1, -1, -1): self._clk((v >> i) & 1)
    def reset_phy(self):
        self.st.update(rst=0, mdc=0, rel=1); self._put(); time.sleep(0.02)
        self.st["rst"] = 1; self._put(); time.sleep(0.3)
    def read(self, phy, reg):
        self._bits(0xFFFFFFFF, 32); self._bits(0b0110, 4); self._bits(phy, 5); self._bits(reg, 5)
        self._clk(None)
        v = 0
        for _ in range(16): v = (v << 1) | self._clk(None)
        return v
    def write(self, phy, reg, val):
        self._bits(0xFFFFFFFF, 32); self._bits(0b0101, 4); self._bits(phy, 5); self._bits(reg, 5); self._bits(0b10, 2); self._bits(val, 16)
        self.st["rel"] = 1; self._put()
    def advertise_gigabit_only(self, phy=0):
        """The MAC's transmit clock is fixed at 125 MHz, so only offer 1000BASE-T full duplex, then restart auto-negotiation."""
        self.write(phy, 4, 0x0001)      # no 10/100 abilities
        self.write(phy, 9, 0x0200)      # 1000BASE-T full duplex only
        self.write(phy, 0, 0x1200)      # auto-negotiation enable + restart
