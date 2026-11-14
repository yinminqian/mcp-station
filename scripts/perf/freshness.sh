#!/bin/bash
# 隐藏 60 秒后切回,数据是不是最新的:calls → overview(60s)→ calls(60s),停在 calls(MCPMAC_SWITCH_STAY=calls)。
# "bench done, staying" 一出现就用 lldb 给窗口截图(App 内 cacheDisplay,不需要屏幕录制权限),并记下当时的时钟。
# 不挂 Instruments;顺带得到 forced 打印的"调用记录页首次进入"和"隐藏 60 秒后再次进入"。
# 用法:scripts/perf/freshness.sh <副本名=step3> "<主题...>" [停留毫秒=60000] [切页次数=3]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; P="$ROOT/scripts/perf"
V="${1:-step3}"; THEMES="${2:-glass bento}"; DWELL="${3:-60000}"; COUNT="${4:-3}"
BIN="$ROOT/build-$V/MCP Mac.app/Contents/MacOS/MCPMac"; RAW="$ROOT/docs/perf/raw"
for theme in $THEMES; do
  log="/tmp/fresh-$V-$theme.stderr.txt"
  MCPMAC_SWITCH_BENCH=1 MCPMAC_SWITCH_MODE=forced MCPMAC_SWITCH_ROUTES=calls,overview MCPMAC_SWITCH_DWELL_MS="$DWELL" \
    MCPMAC_SWITCH_COUNT="$COUNT" MCPMAC_SWITCH_STAY=calls "$BIN" -appearance.theme "$theme" > /dev/null 2> "$log" &
  pid=$!; t0=$(date +%s)
  sleep 1.5; osascript -l JavaScript "$P/winstate.js" "$pid" activate > /dev/null 2>&1
  seen=0
  for _ in $(seq 1 $(( (COUNT * DWELL / 1000 + 60) * 4 ))); do
    if grep -aq "staying" "$log"; then seen=1; break; fi
    # 每 20 秒把窗口重新激活一次,减少被系统降频(App Nap)推迟定时器的机会
    if [ $(( ($(date +%s) - t0) % 20 )) -eq 0 ]; then osascript -l JavaScript "$P/winstate.js" "$pid" activate > /dev/null 2>&1; sleep 1; fi
    sleep 0.25
  done
  now="$(date +%H:%M:%S)"
  png="$RAW/$V-after-hidden-$theme-calls.png"
  sed "s|__PNG__|$png|" "$P/snapshot.lldb" > "/tmp/fresh-$V-$theme.lldb"
  lldb -p "$pid" --batch -s "/tmp/fresh-$V-$theme.lldb" > "/tmp/fresh-$V-$theme.lldb.txt" 2>&1
  sips -Z 1180 "$png" > /dev/null 2>&1
  echo "== $V $theme: staying_seen=$seen 截图时刻(时钟)=$now 用时 $(( $(date +%s) - t0 ))s  $(grep -a SNAPSHOT "/tmp/fresh-$V-$theme.lldb.txt" | tail -1)"
  grep -a '^bench' "$log"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  sleep 1
done
echo FRESH-DONE
