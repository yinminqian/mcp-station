#!/usr/bin/env python3
"""SwiftUI 探针数据汇总:每个切页窗口内,View Body Updates / Representable Updates / Other Updates 的 Top N。
用法:swiftui_top.py <updates.tsv> <runloop.tsv> <routes 逗号分隔,按窗口出现顺序> [topN=10] [min_ms=150] [after_s=5.8]
updates.tsv 由 xctrace_rows.py 从 swiftui-updates 表导出(列:start,duration,update-type,category,module,view-name,description,severity,...)。
注意:开着 SwiftUI 探针时切页本身被拖慢 2~3 倍,这里的毫秒只用来排序和看占比,不是真实耗时。
"""
import csv, sys
from collections import defaultdict
sys.path.insert(0, __import__("os").path.dirname(__file__))
from busy_windows import busy

def main():
    upd, runloop, routes = sys.argv[1], sys.argv[2], sys.argv[3].split(",")
    top = int(sys.argv[4]) if len(sys.argv) > 4 else 10
    min_ms = float(sys.argv[5]) if len(sys.argv) > 5 else 150.0
    after = float(sys.argv[6]) if len(sys.argv) > 6 else 5.8
    merged = []
    for s, e in busy(runloop, 20.0, after):
        if merged and s - merged[-1][1] < 5e6: merged[-1][1] = e
        else: merged.append([s, e])
    wins = [(s, e) for s, e in merged if (e - s) / 1e6 >= min_ms][:len(routes)]
    agg = [defaultdict(lambda: defaultdict(lambda: [0, 0.0, 0.0])) for _ in wins]  # win -> type -> key -> [n, total, max]
    tot = [defaultdict(lambda: [0, 0.0]) for _ in wins]
    for r in csv.DictReader(open(upd, encoding="utf-8"), delimiter="\t"):
        t = int(r["start"])
        for i, (s, e) in enumerate(wins):
            if s <= t <= e:
                d = int(r["duration"] or 0) / 1e6
                ty = r["update-type"]
                key = (r["view-name"] if ty != "Other Updates" else r["description"])[:90] + (f" [{r['module']}]" if ty != "Other Updates" else "")
                a = agg[i][ty][key]; a[0] += 1; a[1] += d; a[2] = max(a[2], d)
                c = tot[i][(ty, r["category"])]; c[0] += 1; c[1] += d
                break
    for i, (s, e) in enumerate(wins):
        print(f"\n## {routes[i]}:窗口 {s/1e9:.3f}s 起,主线程忙 {(e-s)/1e6:.0f} ms(开着 SwiftUI 探针)")
        print("| 更新类型 / 类别 | 次数 | 累计 ms |\n|---|---:|---:|")
        for (ty, cat), (n, d) in sorted(tot[i].items(), key=lambda x: -x[1][1]):
            print(f"| {ty} / {cat} | {n} | {d:.1f} |")
        for ty in ("View Body Updates", "Representable Updates", "Other Updates"):
            print(f"\n**{ty} Top {top}(按累计耗时)**\n\n| 视图 / 属性 | 次数 | 累计 ms | 单次最长 ms |\n|---|---:|---:|---:|")
            for key, (n, d, m) in sorted(agg[i][ty].items(), key=lambda x: -x[1][1])[:top]:
                print(f"| `{key}` | {n} | {d:.1f} | {m:.1f} |")

if __name__ == "__main__":
    main()
