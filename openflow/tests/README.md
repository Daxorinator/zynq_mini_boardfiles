# Board tests

| Test | How |
|---|---|
| Linux-side memory stress (2 threads, random/inverse/address/checker patterns) | `./build_memtest.sh`, then run `build/memtest [MiB per thread] [passes]` on the board; ends with `MEMTEST RESULT: PASS` |
| Bare-metal DDR test (511 MiB, two random patterns by default, `FULL_TEST=1` adds more; uses the hand-written PS7 init) | `../boot/baremetal/build.sh`, then `./run_ddr_test.sh <board-ip>`; the verdict comes from a result code the test leaves in `REBOOT_STATUS` |
| HDMI via the USB capture card | `hdmi_capture/` |

`run_ddr_test.sh` needs no console: it reboots the board into the test (U-Boot one-shot, watchdog armed), waits for a new Linux boot id
and reads the result code. A test that hangs is reset by the watchdog and reported as "did not complete".
