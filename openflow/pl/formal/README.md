# Formal checks (SymbiYosys)

`sby -f hp_dma.sby bmc` proves, for 140 clock steps with a free-running CPU on GP0 and a legal AXI3 slave on HP0, the AXI master rules of the `hp_dma` engine
(valid/address/data held until accepted, WLAST on the 16th beat, no burst crossing a 4 KiB boundary) and that LED done/busy are never both set.

Status 2026-11-18: the first run found two real bugs: (1) an unaligned SRC/DST makes a burst cross a 4 KiB boundary, which AXI forbids (our tests only used aligned buffers);
(2) `mode` was read live, so changing it during a run bypassed the DST alignment check. Fixed in `hp_dma` and `zm_base` (misaligned runs are rejected with the error flag and no bus
traffic; `mode` is latched at start). The proof now passes (bounded model check, 140 steps), `sby -f hp_dma.sby cover` reaches a finished run and an error, the simulations cover the
rejection (`../sim`), and the rebuilt bitstreams pass the hardware tests (`../../py/tests`, incl. rejection of misaligned runs).
The proof is bounded (not an unbounded induction proof) and covers the DMA engine through the HP0 and LED ports only, with a free CPU on GP0.

`sby -f zm_base.sby bmc` runs the same AXI/HP0 rules on `zm_base` (the DMA engine plus the register file, header, timer and clock-meter logic, with the MMCM replaced by free outputs):
passes for 120 steps (about 5 minutes). Not covered: the PL Ethernet MAC front end (`ple_mac`), which has only the offline protocol test and the hardware test.
