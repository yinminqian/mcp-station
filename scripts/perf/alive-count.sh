#!/bin/bash
# "常驻页越多越慢吗":同一个页面在不同的"已常驻页数"下首次进入的耗时。
# 用 MCPMAC_START_ROUTE 改变起点,bench 的切页顺序随之轮转(forced 模式,两个副本都支持)。
# 用法:scripts/perf/alive-count.sh [轮数=3] ["副本..."="step1 step2"] ["起点..."="overview services calls"] [主题=glass]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; P="$ROOT/scripts/perf"
N="${1:-3}"; VARIANTS="${2:-step1 step2}"; STARTS="${3:-overview services calls}"; THEME="${4:-glass}"
OUT="$ROOT/docs/perf/raw"
for i in $(seq 1 "$N"); do
  for start in $STARTS; do
    for v in $VARIANTS; do
      BIN="$ROOT/build-$v/MCP Mac.app/Contents/MacOS/MCPMac"
      f="$OUT/alive-$v-$THEME-start_$start-$i.txt"
      MCPMAC_SWITCH_BENCH=1 MCPMAC_SWITCH_MODE=forced MCPMAC_START_ROUTE="$start" "$BIN" -appearance.theme "$THEME" > /dev/null 2> "$f.tmp" &
      pid=$!
      sleep 1.5; osascript -l JavaScript "$P/winstate.js" "$pid" activate > /dev/null 2>&1
      wait "$pid"
      grep -a '^bench' "$f.tmp" > "$f"; rm -f "$f.tmp"
      echo "== $v start=$start run $i  load: $(uptime | sed 's/.*load averages: //')"; cat "$f"
      sleep 1
    done
  done
done
echo ALL-DONE
