#!/bin/bash
# 空闲 CPU 与内存:第 1 步(停在概览页) vs 第 2 步(全部页面常驻后停在概览页) vs 第 2 步(只开过概览页)。
# 三种条件交替跑,窗口都激活到前台;每种在启动后等同样久再用 top 采 N 秒。
# 用法:scripts/perf/idle-keepalive.sh [轮数=2] [采样秒数=20] ["主题..."="glass bento"]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; P="$ROOT/scripts/perf"
N="${1:-2}"; SECS="${2:-20}"; THEMES="${3:-glass bento}"
OUT="$ROOT/docs/perf/raw"
echo "cond theme run avg% peak% rss_before_MB rss_after_MB footprint | 采样前 | 采样后"
for i in $(seq 1 "$N"); do
  for theme in $THEMES; do
    for cond in step1-fresh step2-alive step2-fresh; do
      v="${cond%%-*}"
      BIN="$ROOT/build-$v/MCP Station.app/Contents/MacOS/MCPStation"
      log="/tmp/idle-ka-$cond-$theme-$i.stderr.txt"
      if [ "$cond" = step2-alive ]; then
        MCPSTATION_SWITCH_BENCH=1 MCPSTATION_SWITCH_STAY=1 MCPSTATION_SWITCH_MODE=forced "$BIN" -appearance.theme "$theme" > /dev/null 2> "$log" &
      else
        "$BIN" -appearance.theme "$theme" > /dev/null 2> "$log" &
      fi
      pid=$!
      t0=$(date +%s)
      sleep 2; osascript -l JavaScript "$P/winstate.js" "$pid" activate > /dev/null 2>&1
      if [ "$cond" = step2-alive ]; then for _ in $(seq 1 80); do grep -aq "staying" "$log" && break; sleep 0.5; done; fi
      # 三种条件都等到启动后 28 秒再开始采样(bench 约 20 秒跑完,留出安定时间)
      while [ $(( $(date +%s) - t0 )) -lt 28 ]; do sleep 0.5; done
      before="$(osascript -l JavaScript "$P/winstate.js" "$pid" 2>&1 | cut -d' ' -f1,2)"
      rss0=$(ps -o rss= -p "$pid" | tr -d ' ')
      f="$OUT/idleka-$cond-$theme-$i.txt"
      top -l $((SECS + 1)) -s 1 -pid "$pid" -stats cpu | awk '/^%CPU/{getline; print $1}' | tail -n "$SECS" > "$f"
      rss1=$(ps -o rss= -p "$pid" | tr -d ' ')
      fp=$(top -l 1 -pid "$pid" -stats mem | tail -1 | tr -d ' ')
      after="$(osascript -l JavaScript "$P/winstate.js" "$pid" 2>&1 | cut -d' ' -f1,2)"
      kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      awk -v p="$cond $theme $i" -v r0="$rss0" -v r1="$rss1" -v fp="$fp" '{s+=$1; if($1>m)m=$1} END{printf "%s %.1f %.1f %.0f %.0f %s", p, s/NR, m, r0/1024, r1/1024, fp}' "$f"
      echo " | $before | $after"
      sleep 1
    done
  done
done
echo ALL-DONE
