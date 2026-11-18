# Formal checks (SymbiYosys)

`sby -f hp_dma.sby bmc` proves, for 140 clock steps with a free-running CPU on GP0 and a legal AXI3 slave on HP0, the AXI master rules of the `hp_dma` engine
(valid/address/data held until accepted, WLAST on the 16th beat, no burst crossing a 4 KiB boundary) and that LED done/busy are never both set.

Status 2026-11-18: the first run found a real bug (an unaligned SRC/DST makes a burst cross a 4 KiB boundary, which AXI forbids; our tests only used aligned buffers).
`hp_dma` and `zm_base` now reject misaligned runs with the error flag (simulation passes; NOT yet rebuilt or tried on hardware). The proof still fails at step 51 on the
write address: `mode` is read live, so changing it while a run is busy bypasses the DST alignment check. Fix: latch `mode` at start. Open.
