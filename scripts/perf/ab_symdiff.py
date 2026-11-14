#!/usr/bin/env python3
"""探索用:某个页面的切页窗口里,两个版本的 inclusive 符号毫秒数对比,按差值排序。
用法:ab_symdiff.py <目录> <轮次列表> <route> [topN=40] [只看独占归类含此子串的采样] [符号过滤正则] [sort=diff|b] [variantA,variantB=baseline,step1] [all|first|again]
"""
import csv, os, re, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(__file__))
from ab_summary import windows, ROUTES
from switch_profile import classify
csv.field_size_limit(10**9)
d, rounds, route = sys.argv[1], [int(x) for x in sys.argv[2].split(",")], sys.argv[3]
top = int(sys.argv[4]) if len(sys.argv) > 4 else 40
bucket = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] else None
pat = re.compile(sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6] else None
sort = sys.argv[7] if len(sys.argv) > 7 and sys.argv[7] else "diff"
VA, VB = (sys.argv[8] if len(sys.argv) > 8 else "baseline,step1").split(",")
kind = sys.argv[9] if len(sys.argv) > 9 else "all"
res = {}
for v in (VA, VB):
    inc, n = Counter(), 0
    for i in rounds:
        base = os.path.join(d, f"tp-{v}-{i}")
        w, _ = windows(base + ".runloop.tsv", base + ".samples.tsv", v)
        mine = [x for k, x in enumerate(w[:15]) if ROUTES[k % 5] == route and (kind == "all" or kind == ("first" if k < 4 else "again"))]
        n += len(mine)
        for row in csv.DictReader(open(base + ".samples.tsv", encoding="utf-8"), delimiter="\t"):
            if not row["thread"].startswith("Main Thread"): continue
            t = int(row["time"])
            if not any(s <= t <= e for s, e in mine): continue
            if bucket and bucket not in classify(row["stack"])[0]: continue
            for f in set(row["stack"].split("|")): inc[f] += 1
    res[v] = {f: c / n for f, c in inc.items()}
keys = set(res[VA]) | set(res[VB])
rows = [(res[VB].get(f, 0) - res[VA].get(f, 0), res[VA].get(f, 0), res[VB].get(f, 0), f) for f in keys if not pat or pat.search(f)]
rows.sort(key=(lambda r: -r[0]) if sort == "diff" else (lambda r: -r[2]))
print(f"  diff      A      B  symbol   (A={VA}, B={VB}, {kind})")
for dlt, b, s, f in rows[:top]:
    print(f"{dlt:+6.1f} {b:6.1f} {s:6.1f}  {f[:150]}")
