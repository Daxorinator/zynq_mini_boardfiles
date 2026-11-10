#!/usr/bin/env python3
"""
Test the PS-side LED (D6, MIO9, active high) and KEY1 (MIO0, active low) with PYNQ's GPIO class.

Run as root on the board: python3 ps_gpio_test.py
"""
import time
from pynq import GPIO

MIO_LED = 9     # D6, active high
MIO_KEY1 = 0    # KEY1, pulled up to 3.3 V, closes to GND (active low)

base = GPIO.get_gpio_base()          # sysfs number of the PS GPIO controller's first pin (MIO0)
print("PS GPIO base:", base)

led = GPIO(base + MIO_LED, "out")
key = GPIO(base + MIO_KEY1, "in")

print("Blinking the PS LED 5 times...")
for _ in range(5):
    led.write(1); time.sleep(0.25)
    led.write(0); time.sleep(0.25)

print("Press KEY1 (Ctrl-C to stop). LED lights while the key is held.")
try:
    last = None
    while True:
        pressed = (key.read() == 0)
        led.write(1 if pressed else 0)
        if pressed != last:
            print("KEY1", "pressed" if pressed else "released")
            last = pressed
        time.sleep(0.02)
except KeyboardInterrupt:
    pass
finally:
    led.write(0)
    led.release()
    key.release()
