#!/usr/bin/env python3
"""Tell a real captured picture from the USB capture card's own no-signal screen (which is also colour bars).
usage: classify.py capture.png [...]    compares against card_nosignal_placeholder.png next to this script."""
import os, sys
from PIL import Image
import numpy as np
here = os.path.dirname(os.path.abspath(__file__))
ref = np.asarray(Image.open(os.path.join(here, "card_nosignal_placeholder.png")).convert("RGB")).astype(int)
for p in sys.argv[1:]:
    a = np.asarray(Image.open(p).convert("RGB")).astype(int)
    if a.shape != ref.shape:
        print("%s: size %s differs from the 640x480 reference, judge by eye" % (os.path.basename(p), a.shape[:2])); continue
    diff = np.abs(a - ref).mean()
    noise = (np.abs(np.diff(a, axis=1)).sum(2) > 60).mean()
    print("%-28s diff_from_nosig=%6.2f noise=%.3f -> %s" % (os.path.basename(p), diff, noise,
          "NO SIGNAL" if diff < 1 else ("SIGNAL, noisy" if noise > 0.1 else "SIGNAL clean?")))
