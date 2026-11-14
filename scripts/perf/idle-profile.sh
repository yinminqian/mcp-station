#!/bin/bash
# 空闲时在忙什么:对"全部页面常驻后停在概览页"和"只开过概览页"各 attach 录 10 秒 Time Profiler,
# 输出主线程每秒耗时,以及按 App 自己的符号(@MCPMac)和几类框架符号统计的每秒毫秒数。
# 用法:scripts/perf/idle-profile.sh <副本名=step2> <主题=glass> <输出目录=/tmp/mcpmac-perf3>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; P="$ROOT/scripts/perf"
V="${1:-step2}"; THEME="${2:-glass}"; OUT="${3:-/tmp/mcpmac-perf3}"
BIN="$ROOT/build-$V/MCP Mac.app/Contents/MacOS/MCPMac"
cd "$OUT"
for mode in alive fresh; do
  log="idleprof-$THEME-$mode.stderr.txt"; t="idleprof-$THEME-$mode"
  if [ "$mode" = alive ]; then
    MCPMAC_SWITCH_BENCH=1 MCPMAC_SWITCH_STAY=1 MCPMAC_SWITCH_MODE=forced "$BIN" -appearance.theme "$THEME" > /dev/null 2> "$log" &
  else
    "$BIN" -appearance.theme "$THEME" > /dev/null 2> "$log" &
  fi
  pid=$!; t0=$(date +%s)
  sleep 2; osascript -l JavaScript "$P/winstate.js" "$pid" activate > /dev/null 2>&1
  if [ "$mode" = alive ]; then for _ in $(seq 1 80); do grep -aq "staying" "$log" && break; sleep 0.5; done; fi
  while [ $(( $(date +%s) - t0 )) -lt 26 ]; do sleep 0.5; done
  rm -rf "$t.trace"
  xcrun xctrace record --template 'Time Profiler' --output "$t.trace" --time-limit 10s --attach "$pid" > "$t.rec.log" 2>&1
  echo "$mode: $(osascript -l JavaScript "$P/winstate.js" "$pid" 2>&1 | cut -d' ' -f1,2)"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  xcrun xctrace export --input "$t.trace" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > "$t.tp.xml" 2>/dev/null
  python3 "$P/tp_dump.py" "$t.tp.xml" "$t.samples.tsv"; rm -f "$t.tp.xml"
done
python3 - "$OUT/idleprof-$THEME-alive.samples.tsv" "$OUT/idleprof-$THEME-fresh.samples.tsv" <<'PY'
import csv, re, sys
from collections import Counter
csv.field_size_limit(10**9)
MARK = [("NSTableView(任意帧)", r"NSTableView|NSTableRow|NSOutlineView|AppKitOutlineTable|SwiftUITable|TableCellHosting"),
        ("Charts", r"@Charts$"), ("属性图求值", r"AG::Graph::UpdateStack::update"), ("NSHostingView.layout", r"NSHostingView\.layout"),
        ("环境值下发", r"updateEnvironment|adoptEnvironment"), ("CA 提交", r"CA::Transaction::commit"),
        ("图层绘制", r"CA::Layer::display_|CABackingStore|CGDisplayList|drawRect"), ("文字", r"@CoreText$|Text\.resolve|ResolvedText|NSCoreTypesetter"),
        ("工具栏", r"NSToolbar|ToolbarBridge|AppKitToolbar"), ("sizeThatFits", r"sizeThatFits")]
MARK = [(n, re.compile(p)) for n, p in MARK]
res = {}
for path in sys.argv[1:]:
    tot = 0.0; app = Counter(); mk = Counter(); t = []
    for r in csv.DictReader(open(path, encoding="utf-8"), delimiter="\t"):
        if not r["thread"].startswith("Main Thread"): continue
        w = int(r["weight"]) / 1e6; tot += w; t.append(int(r["time"]))
        fr = set(r["stack"].split("|"))
        for f in fr:
            if f.endswith("@MCPMac"): app[f] += w
        for n, rx in MARK:
            if any(rx.search(f) for f in fr): mk[n] += w
    secs = (max(t) - min(t)) / 1e9 if t else 1
    res[path] = (tot / secs, {k: v / secs for k, v in app.items()}, {k: v / secs for k, v in mk.items()})
(a_tot, a_app, a_mk), (f_tot, f_app, f_mk) = res[sys.argv[1]], res[sys.argv[2]]
print(f"主线程在 CPU 上的时间(ms/秒): 全部常驻 {a_tot:.1f}  只开概览 {f_tot:.1f}")
print("| 标记(可重叠) | 全部常驻 ms/秒 | 只开概览 ms/秒 |\n|---|---:|---:|")
for n, _ in MARK: print(f"| {n} | {a_mk.get(n, 0):.1f} | {f_mk.get(n, 0):.1f} |")
print("| App 符号(@MCPMac,前 25,按全部常驻排序) | 全部常驻 ms/秒 | 只开概览 ms/秒 |\n|---|---:|---:|")
for k, v in sorted(a_app.items(), key=lambda x: -x[1])[:25]: print(f"| `{k[:110]}` | {v:.2f} | {f_app.get(k, 0):.2f} |")
PY
