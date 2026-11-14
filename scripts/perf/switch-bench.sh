#!/bin/bash
# 切页 bench：两套主题各跑 N 次 MCPSTATION_SWITCH_BENCH=1，原始 stderr 存到 docs/perf/raw/。
# 主题用 NSUserDefaults 参数域（-appearance.theme <x>）传入，不写持久 defaults，
# 不会影响正在运行的其他 MCP Station 实例。
# 用法：scripts/perf/switch-bench.sh [次数=3]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/build/MCP Station.app/Contents/MacOS/MCPStation"
OUT="$ROOT/docs/perf/raw"
N="${1:-3}"
mkdir -p "$OUT"
for theme in glass bento; do
  for i in $(seq 1 "$N"); do
    f="$OUT/bench-$theme-$i.txt"
    MCPSTATION_SWITCH_BENCH=1 "$BIN" -appearance.theme "$theme" 2>&1 | grep '^bench ' > "$f" || true
    echo "== $theme run $i"; cat "$f"
    sleep 2
  done
done
