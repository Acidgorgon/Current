#!/usr/bin/env python3
"""Print markdown tables comparing result files.

    python3 tables.py results/plus.json results/stock.json ...

Columns follow the order of the arguments; the column name is each file's label.
The best value in each row is bold. The `remotes` baseline is never marked best:
the mock does not time Roblox's own serialization of its tables (see README).
"""
import json
import sys

files = sys.argv[1:]
if not files:
    sys.exit(__doc__)
data = [json.load(open(f)) for f in files]
labels = [d["label"] for d in data]

scenarios = []
for d in data:
    for s in d["scenarios"]:
        if s not in scenarios:
            scenarios.append(s)


def num(x, digits=0):
    return f"{x:,.{digits}f}"


def cell(d, s, f):
    e = d["scenarios"].get(s)
    if e is None:
        return "–"
    if "skipped" in e:
        return "n/a"
    if "error" in e:
        return "error"
    try:
        return f(e)
    except (KeyError, TypeError):
        return "–"


def phase(mode, name, key="us"):
    return lambda e: e[mode]["phases"][name][key]


def best_marked(values, lower_is_better=True):
    nums = [v for v in values if isinstance(v, (int, float))]
    best = (min if lower_is_better else max)(nums) if nums else None
    return best


TABLES = [
    ("CPU per frame, native codegen (µs, server + all clients)", phase("native", "total"), 1),
    ("CPU per frame, interpreter (µs, server + all clients)", phase("interp", "total"), 1),
    ("Receive cost per client, native (µs)", phase("native", "client_recv_per_client"), 2),
    ("Library allocations per frame (bytes, interpreter)", phase("interp", "total", "alloc_bytes"), 0),
    ("Wire bytes per frame (all receivers, s2c + c2s)",
     lambda e: e["interp"]["wire"]["s2c_bytes_per_frame"] + e["interp"]["wire"]["c2s_bytes_per_frame"], 0),
    ("Client module memory (KB, code + state)", lambda e: e["interp"]["heap"]["client_module"] / 1024, 1),
    ("Server module memory (KB, code + state)", lambda e: e["interp"]["heap"]["server_module"] / 1024, 1),
]

for title, f, digits in TABLES:
    print(f"\n### {title}\n")
    print("| scenario | " + " | ".join(labels) + " |")
    print("|---|" + "---:|" * len(labels))
    for s in scenarios:
        raw = []
        for d in data:
            v = cell(d, s, f)
            raw.append(v)
        best = best_marked([v for v, l in zip(raw, labels) if l != "remotes"])
        out = []
        for v, label in zip(raw, labels):
            if isinstance(v, (int, float)):
                txt = num(v, digits)
                out.append(f"**{txt}**" if v == best and label != "remotes" else txt)
            else:
                out.append(v)
        print(f"| {s} | " + " | ".join(out) + " |")
