# Formal checks (SymbiYosys)

`sby -f hp_dma.sby bmc` proves, for 140 clock steps with a free-running CPU on GP0 and a legal AXI3 slave on HP0, the AXI master rules of the `hp_dma` engine
(valid/address/data held until accepted, WLAST on the 16th beat, no burst crossing a 4 KiB boundary) and that LED done/busy are never both set.

Status 2026-11-18: the first run found two real bugs: (1) an unaligned SRC/DST makes a burst cross a 4 KiB boundary, which AXI forbids (our tests only used aligned buffers);
(2) `mode` was read live, so changing it during a run bypassed the DST alignment check. Fixed in `hp_dma` and `zm_base` (misaligned runs are rejected with the error flag and no bus
traffic; `mode` is latched at start). The proof now passes (bounded model check, 140 steps), `sby -f hp_dma.sby cover` reaches a finished run and an error, the simulations cover the
rejection (`../sim`), and the rebuilt bitstreams pass the hardware tests (`../../py/tests`, incl. rejection of misaligned runs).
The proof is bounded (not an unbounded induction proof) and covers the DMA engine through the HP0 and LED ports only, with a free CPU on GP0.

`sby -f zm_base.sby bmc` runs the same AXI/HP0 rules on `zm_base` (the DMA engine plus the register file, header, timer and clock-meter logic, with the MMCM replaced by free outputs):
passes for 120 steps (about 5 minutes). `./run_ple_mac.sh [bmc|cover]` checks the PL Ethernet MAC front end (`ple_mac`): invariants on the TX state machine (state encoding, TXEN low when idle, preamble/gap counters in range, data only with TXEN) and the RX side
(byte index within the 320-byte buffer, a frame in progress and a ready frame never coexist, stored length fits), proven for 150 steps with free clocks and a free PHY; the cover goals (a transmitted frame can complete,
a received frame can become ready) are reached. A mutant that makes the TX state machine hang in the gap state is caught by the cover goal, a mutant that lets TXEN stay high when idle and one that accepts a frame while the
buffer is full are caught by the invariants. Not caught by the bounded proof: a changed buffer limit (320 -> 330 needs over 300 bytes of depth); the simulation `../sim/tb_ple_mac.v` covers that one.
The properties are written in `ple_mac_props.vh` and included into a generated copy of the design (Yosys cannot bind assertions to internal signals); `PLE_MAC_SRC` points the script at a different source for mutation checks.
