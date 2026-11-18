#!/usr/bin/env python3
"""Decode the Vivado-generated ps7_init_gpl.c (silicon 3.0 tables) into an operation list with named fields.
Used only as the REFERENCE the hand-written init is checked against (trace equivalence); the hand-written init does not need it."""
import re, json, sys
SRC = sys.argv[1] if len(sys.argv) > 1 else "vivado_ref/ps7_init_gpl.c"
s = open(SRC).read()
SECTIONS = ["mio", "pll", "clock", "ddr", "peripherals", "post_config", "debug"]
def block(name):
    i = s.index("unsigned long %s[] = {" % name); return s[i:s.index("};", i)]
ops_by_sec = {}
for sec in SECTIONS:
    name = ("ps7_%s_init_data_3_0" % sec) if sec not in ("post_config", "debug") else ("ps7_%s_3_0" % sec)
    lines = block(name).splitlines()
    ops, fields, path = [], [], []
    for l in lines:
        t = l.strip()
        m = re.match(r"// \.\. (?:\.\. )*START: (.*)", t)
        if m: path.append(m.group(1)); continue
        m = re.match(r"// \.\. (?:\.\. )*FINISH: (.*)", t)
        if m:
            if path: path.pop()
            continue
        m = re.match(r"// \.\. (?:\.\. )*==> (0X[0-9A-F]+)\[(\d+):(\d+)\] = (0x[0-9A-Fa-f]+)U", t)
        if m and fields:
            fields[-1].update(addr=m.group(1), hi=int(m.group(2)), lo=int(m.group(3)), val=int(m.group(4), 16)); continue
        m = re.match(r"// \.\. (?:\.\. )*([A-Za-z0-9_]+) = (\S+)$", t)
        if m and "MASK" not in t and "==>" not in t:
            fields.append({"name": m.group(1), "text": m.group(2)}); continue
        m = re.match(r"EMIT_(\w+)\(([^)]*)\)", t)
        if m:
            args = [a.strip().rstrip("U") for a in m.group(2).split(",") if a.strip()]
            args = [int(a, 16) if a.lower().startswith("0x") else int(a) for a in args]
            ops.append({"op": m.group(1), "args": args, "path": " / ".join(path),
                        "fields": [f for f in fields if "addr" in f]})
            fields = []
    ops_by_sec[sec] = ops
json.dump(ops_by_sec, open("ps7_model.json", "w"), indent=1)
# readable summary
with open("ps7_model.md", "w") as o:
    for sec, ops in ops_by_sec.items():
        o.write("## %s (%d ops)\n\n" % (sec, len(ops)))
        for op in ops:
            a = op["args"]
            if op["op"] == "MASKWRITE": o.write("- MASKWRITE %#010x mask=%#010x val=%#010x   [%s]\n" % (a[0], a[1], a[2], op["path"]))
            elif op["op"] == "WRITE": o.write("- WRITE     %#010x val=%#010x   [%s]\n" % (a[0], a[1], op["path"]))
            elif op["op"] in ("MASKPOLL", "MASKDELAY"): o.write("- %s %#010x mask=%#010x   [%s]\n" % (op["op"], a[0], a[1], op["path"]))
            else: o.write("- %s\n" % op["op"])
            for f in op["fields"]:
                o.write("    - %s = %s  (bits %d:%d of %s)\n" % (f["name"], f["text"], f["hi"], f["lo"], f["addr"]))
        o.write("\n")
print({k: len(v) for k, v in ops_by_sec.items()})
