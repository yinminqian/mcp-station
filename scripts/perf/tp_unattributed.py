#!/usr/bin/env python3
"""探索用:某个页面窗口内、独占归类为指定桶的采样里,inclusive 符号排行。
用法:tp_unattributed.py <samples.tsv> <runloop.tsv> <route> <桶名子串> [topN=60] [过滤正则]
"""
import csv, re, sys
from collections import Counter
sys.path.insert(0, __import__("os").path.dirname(__file__))
from busy_windows import busy
from switch_profile import classify
csv.field_size_limit(10**9)
samples, runloop, route, bucket = sys.argv[1:5]
top = int(sys.argv[5]) if len(sys.argv) > 5 else 60
pat = re.compile(sys.argv[6]) if len(sys.argv) > 6 else None
routes = "mcps,services,calls,settings,overview".split(",")
merged = []
for s, e in busy(runloop, 20.0, 4.5):
    if merged and s - merged[-1][1] < 5e6: merged[-1][1] = e
    else: merged.append([s, e])
wins = [(s, e) for s, e in merged if (e - s) / 1e6 >= 50]
mine = [w for i, w in enumerate(wins) if routes[i % 5] == route]
inc, n = Counter(), 0
for r in csv.DictReader(open(samples, encoding="utf-8"), delimiter="\t"):
    if not r["thread"].startswith("Main Thread"): continue
    t = int(r["time"])
    if not any(s <= t <= e for s, e in mine): continue
    c, _ = classify(r["stack"])
    if bucket not in c: continue
    n += 1
    for f in set(r["stack"].split("|")): inc[f] += 1
print("samples", n, "over", len(mine), "switches")
k = 0
for f, c in inc.most_common():
    if pat and not pat.search(f): continue
    print(f"{c:5d} {100*c/n:5.1f}%  {f[:150]}")
    k += 1
    if k >= top: break
