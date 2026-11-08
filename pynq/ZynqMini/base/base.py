from pynq import Overlay


class BaseOverlay(Overlay):
    """PS-only overlay for the ZYNQ MINI (empty PL)."""
    def __init__(self, bitfile="base.bit", **kwargs):
        super().__init__(bitfile, **kwargs)
