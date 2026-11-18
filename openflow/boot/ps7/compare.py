#!/usr/bin/env python3
"""Compare the open init's register trace (from trace_host) with the Vivado-generated tables (ps7_model.json)."""
import json, subprocess, sys
m = json.load(open("ps7_model.json"))
def ref(secs):
    t = []
    for s in secs:
        for o in m[s]:
            a = o["args"]
            if o["op"] == "WRITE": t.append(("W", a[0], a[1]))
            elif o["op"] == "MASKWRITE": t.append(("M", a[0], a[1], a[2] & a[1]))
            elif o["op"] == "MASKPOLL": t.append(("P", a[0], a[1]))
            elif o["op"] == "MASKDELAY": t.append(("D", a[1]))
    return t
def mine(lines):
    t = []
    for l in lines:
        p = l.split()
        if p[0] == "W": t.append(("W", int(p[1], 16), int(p[2], 16)))
        elif p[0] == "M": t.append(("M", int(p[1], 16), int(p[2], 16), int(p[3], 16)))
        elif p[0] == "P": t.append(("P", int(p[1], 16), int(p[2], 16)))
        elif p[0] == "D": t.append(("D", int(p[1])))
    return t
out = subprocess.run(["./trace_host"], capture_output=True, text=True).stdout.splitlines()
i = [k for k, l in enumerate(out) if l.startswith("# init")][0]
got_init, got_post = mine(out[:i]), mine(out[i + 1:-1])
bad = 0
for name, got, want in (("init", got_init, ref(["mio", "pll", "clock", "ddr", "peripherals"])), ("post_config", got_post, ref(["post_config"]))):
    n = 0
    for k in range(max(len(got), len(want))):
        g = got[k] if k < len(got) else None; w = want[k] if k < len(want) else None
        if g != w:
            n += 1
            if n <= 12: print("%s op %d: mine=%s vivado=%s" % (name, k, g, w))
    print("%s: %d ops mine, %d ops vivado, %d differences" % (name, len(got), len(want), n)); bad += n
print("TRACES IDENTICAL" if bad == 0 else "MISMATCH"); sys.exit(1 if bad else 0)
