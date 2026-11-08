# Run as root on the board, from the folder holding leds_keys.bit/.hwh
import time
from pynq import Overlay

ol = Overlay("leds_keys.bit")
leds = ol.leds        # AXI GPIO, 4 outputs (LED1..LED4)
keys = ol.keys        # AXI GPIO, 2 inputs (KEY2, KEY3), active low

for i in range(3):                      # chase pattern
    for bit in (1, 2, 4, 8, 4, 2):
        leds.write(0x0, bit)            # channel 1 data register
        time.sleep(0.15)
leds.write(0x0, 0)

print("Press KEY2 / KEY3 (Ctrl-C to stop)")
try:
    while True:
        k = keys.read(0x0) & 0x3        # active low: 0 = pressed
        leds.write(0x0, (~k) & 0x3)     # LED1 = KEY2, LED2 = KEY3
        time.sleep(0.02)
except KeyboardInterrupt:
    leds.write(0x0, 0)
