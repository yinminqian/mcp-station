#!/bin/bash
# 内存走势:启动后每 10 秒记一次 RSS、top 的 MEM(footprint)和这 10 秒的平均 CPU,共 N 次。
# 用法:scripts/perf/mem-watch.sh <副本名> <主题> <alive|fresh> [次数=12]
#   alive = MCPMAC_SWITCH_BENCH=1 MCPMAC_SWITCH_STAY=1(只有第 2 步副本支持),全部页面常驻后停在概览页
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; P="$ROOT/scripts/perf"
V="$1"; THEME="$2"; MODE="$3"; N="${4:-12}"
BIN="$ROOT/build-$V/MCP Mac.app/Contents/MacOS/MCPMac"
log="/tmp/memwatch-$V-$THEME-$MODE.stderr.txt"
if [ "$MODE" = alive ]; then
  MCPMAC_SWITCH_BENCH=1 MCPMAC_SWITCH_STAY=1 MCPMAC_SWITCH_MODE=forced "$BIN" -appearance.theme "$THEME" > /dev/null 2> "$log" &
else
  "$BIN" -appearance.theme "$THEME" > /dev/null 2> "$log" &
fi
pid=$!; t0=$(date +%s)
sleep 2; osascript -l JavaScript "$P/winstate.js" "$pid" activate > /dev/null 2>&1
if [ "$MODE" = alive ]; then for _ in $(seq 1 80); do grep -aq "staying" "$log" && break; sleep 0.5; done; fi
while [ $(( $(date +%s) - t0 )) -lt 25 ]; do sleep 0.5; done
echo "# $V $THEME $MODE   t(s since launch)  rss_MB  top_MEM  cpu%(10s avg)  active"
for _ in $(seq 1 "$N"); do
  cpu=$(top -l 11 -s 1 -pid "$pid" -stats cpu | awk '/^%CPU/{getline; if(n++>0){s+=$1}} END{printf "%.1f", s/(n-1)}')
  rss=$(ps -o rss= -p "$pid" | tr -d ' ')
  mem=$(top -l 1 -pid "$pid" -stats mem | tail -1 | tr -d ' ')
  act=$(osascript -l JavaScript "$P/winstate.js" "$pid" 2>&1 | cut -d' ' -f1)
  echo "$(( $(date +%s) - t0 )) $((rss / 1024)) $mem $cpu $act"
done
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
