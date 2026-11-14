#!/usr/bin/env python3
"""每次切页的阻塞指标(适用于有持续动画的主题,比如 bento:动画帧会让"合并忙区间"虚高)。
对每个切页(= 调用栈含 bench 帧 Snapshotter 的那个主线程忙段),在其后 450ms 内统计:
  first   首段阻塞:切页所在的那一个不间断忙段(ms)——用户感到的"卡住"
  merged  合并忙区间:与报告 01/02 相同,相邻间隔 <5ms 的忙段并成一次(ms)
  late    超帧累计:窗口内每个忙段超出一帧(8.33ms)的部分之和(ms)——卡住 + 动画掉帧
  worst   首段之后最长的单个忙段(ms)——动画里最慢的一帧
用法:switch_metrics.py <目录> <轮次列表> <variant,variant...>     文件名 tp-<variant>-<轮>.{runloop,samples}.tsv
输出:每页 首次/再次 的各指标中位数,以及逐次数值。
"""
import csv, os, sys
from statistics import median
sys.path.insert(0, os.path.dirname(__file__))
from busy_windows import busy, is_switch_sample
csv.field_size_limit(10**9)
ROUTES = "mcps,services,calls,settings,overview".split(",")
FRAME = 8.33

def switches(base):
    raw = busy(base + ".runloop.tsv", 0.3, 4.0)
    hits = [0] * len(raw); k = 0
    for row in csv.DictReader(open(base + ".samples.tsv", encoding="utf-8"), delimiter="\t"):
        if not row["thread"].startswith("Main Thread") or not is_switch_sample(row["stack"]): continue
        t = int(row["time"])
        while k < len(raw) and raw[k][1] < t: k += 1
        if k < len(raw) and raw[k][0] <= t: hits[k] += 1
    idx = [i for i, h in enumerate(hits) if h >= 2]
    out = []
    for i in idx:
        s0, e0 = raw[i]
        first = (e0 - s0) / 1e6
        # 合并忙区间(间隔 <5ms)
        e = e0; j = i + 1
        while j < len(raw) and raw[j][0] - e < 5e6: e = raw[j][1]; j += 1
        merged = (e - s0) / 1e6
        segs = [(b - a) / 1e6 for a, b in raw[i:] if a < s0 + 450e6]
        late = sum(max(0.0, d - FRAME) for d in segs)
        worst = max(segs[1:]) if len(segs) > 1 else 0.0
        out.append(dict(first=first, merged=merged, late=late, worst=worst))
    return out

def main():
    d, rounds, variants = sys.argv[1], [int(x) for x in sys.argv[2].split(",")], sys.argv[3].split(",")
    order = ["mcps", "services", "calls", "overview", "settings"]
    data = {v: {r: {"first": [], "again": []} for r in ROUTES} for v in variants}
    for v in variants:
        for i in rounds:
            sw = switches(os.path.join(d, f"tp-{v}-{i}"))
            print(f"<!-- {v} round {i}: {len(sw)} switches; first: {' '.join('%.0f' % x['first'] for x in sw)} -->")
            for k, x in enumerate(sw[:15]):
                data[v][ROUTES[k % 5]]["first" if k < 4 else "again"].append(x)
    for metric, title in (("first", "首段阻塞"), ("merged", "合并忙区间(间隔<5ms)"), ("late", "超帧累计"), ("worst", "首段之后最长单段")):
        print(f"\n## {title}(ms,中位数)\n\n| 页面 | " + " | ".join(f"{v} 首次 | {v} 再次" for v in variants) + " |\n|---|" + "---:|" * (2 * len(variants)))
        for r in order:
            cells = []
            for v in variants:
                for kind in ("first", "again"):
                    xs = [x[metric] for x in data[v][r][kind]]
                    cells.append(f"{median(xs):.0f}" if xs else "—")
            print(f"| {r} | " + " | ".join(cells) + " |")
    print("\n## 逐次数值(首段阻塞 / 超帧累计)\n")
    for r in order:
        for v in variants:
            for kind in ("first", "again"):
                xs = data[v][r][kind]
                if xs: print(f"- {r} {v} {kind}: " + " ".join("%.0f/%.0f" % (x["first"], x["late"]) for x in xs))

if __name__ == "__main__":
    main()
