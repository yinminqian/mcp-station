#!/bin/bash
# 点击穿透检查(不需要辅助功能权限):用 lldb 附加到进程,在窗口上按 48×32 网格调用 AppKit 的 hitTest:,
# 记录每个点命中的视图类,以及它有没有"不可见的祖先"(isHidden / alpha≈0 / layer.opacity≈0)。
# 两种状态各做一次并比较:A 只访问过概览页;B 访问过全部页面后回到概览页(MCPSTATION_SWITCH_STAY=1)。
# 只读:hitTest: 不产生事件。局限:SwiftUI 自绘控件的命中在 NSHostingView 内部决定,这里看不到。
# 用法:scripts/perf/hittest.sh <副本名=step2> <主题=glass> <输出目录=/tmp/mcpstation-perf3>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; P="$ROOT/scripts/perf"
V="${1:-step2}"; THEME="${2:-glass}"; OUT="${3:-/tmp/mcpstation-perf3}"
BIN="$ROOT/build-$V/MCP Station.app/Contents/MacOS/MCPStation"
mkdir -p "$OUT"
for state in fresh alive; do
  log="$OUT/hit-$THEME-$state.stderr.txt"
  if [ "$state" = alive ]; then
    MCPSTATION_SWITCH_BENCH=1 MCPSTATION_SWITCH_STAY=1 MCPSTATION_SWITCH_MODE=forced MCPSTATION_SWITCH_COUNT=5 "$BIN" -appearance.theme "$THEME" > /dev/null 2> "$log" &
  else
    "$BIN" -appearance.theme "$THEME" > /dev/null 2> "$log" &
  fi
  pid=$!
  sleep 2; osascript -l JavaScript "$P/winstate.js" "$pid" activate > /dev/null 2>&1
  if [ "$state" = alive ]; then for _ in $(seq 1 60); do grep -aq "staying" "$log" && break; sleep 0.5; done; fi
  sleep 3
  lldb -p "$pid" --batch -s "$P/hittest.lldb" > "$OUT/hit-$THEME-$state.lldb.txt" 2>&1
  grep -aE '^[0-9]+,[0-9]+,' "$OUT/hit-$THEME-$state.lldb.txt" > "$OUT/hit-$THEME-$state.map.txt"
  echo "$state: $(wc -l < "$OUT/hit-$THEME-$state.map.txt") points; $(grep -a HITMAP "$OUT/hit-$THEME-$state.lldb.txt" | head -1)"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  sleep 1
done
python3 - "$OUT/hit-$THEME-fresh.map.txt" "$OUT/hit-$THEME-alive.map.txt" <<'PY'
import sys
from collections import Counter
def load(p): return {tuple(l.split(",")[:2]): l.strip().split(",")[2:] for l in open(p)}
a, b = load(sys.argv[1]), load(sys.argv[2])
print("命中类分布 fresh:", Counter(v[0] for v in a.values()).most_common(12))
print("命中类分布 alive:", Counter(v[0] for v in b.values()).most_common(12))
diff = [(k, a[k], b[k]) for k in sorted(a, key=lambda k: (int(k[1]), int(k[0]))) if k in b and a[k][0] != b[k][0]]
inv_a = [k for k, v in a.items() if v[1] != "-"]; inv_b = [(k, v) for k, v in b.items() if v[1] != "-"]
print(f"两种状态命中类不同的点: {len(diff)} / {len(a)}")
for k, x, y in diff[:40]: print("  ", k, x, "->", y)
print(f"命中视图带不可见祖先的点: fresh {len(inv_a)}, alive {len(inv_b)}")
for k, v in inv_b[:20]: print("  ", k, v)
PY
