#!/usr/bin/env python3
"""探索用:列出给定时间窗内主线程样本的 inclusive 符号排行。
用法:tp_explore.py <samples.tsv> <start_s,end_s[;start_s,end_s...]> [topN=80] [过滤正则]
"""
import csv, re, sys
from collections import Counter
csv.field_size_limit(10**9)
wins = [tuple(float(x) for x in w.split(",")) for w in sys.argv[2].split(";")]
top = int(sys.argv[3]) if len(sys.argv) > 3 else 80
pat = re.compile(sys.argv[4]) if len(sys.argv) > 4 else None
inc, leafbin, n = Counter(), Counter(), 0
for r in csv.DictReader(open(sys.argv[1], encoding="utf-8"), delimiter="\t"):
    if not r["thread"].startswith("Main Thread"): continue
    t = int(r["time"]) / 1e9
    if not any(a <= t <= b for a, b in wins): continue
    n += 1
    fr = r["stack"].split("|")
    leafbin[fr[0].rsplit("@", 1)[-1]] += 1
    for f in set(fr): inc[f] += 1
print("samples", n)
print("leaf binaries:", leafbin.most_common(15))
k = 0
for f, c in inc.most_common():
    if pat and not pat.search(f): continue
    print(f"{c:5d} {100*c/n:5.1f}%  {f[:170]}")
    k += 1
    if k >= top: break
