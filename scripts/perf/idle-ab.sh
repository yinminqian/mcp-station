#!/bin/bash
# 空闲 CPU 与内存(通用版):若干"条件"交替跑,每个条件写成 <副本>:<模式>:<页面>。
#   模式 fresh  = 直接以该页面启动(MCPMAC_START_ROUTE)
#        alive  = 跑完默认 16 次切页后停在该页面(MCPMAC_SWITCH_BENCH=1 MCPMAC_SWITCH_STAY=<页面>,forced),全部页面常驻
#        closed = 启动 2 秒后关掉主窗口(MCPMAC_CLOSE_TEST=1),进程继续运行
# fresh / alive 在启动后和采样前各激活一次窗口;closed 不激活。启动后 26 秒开始,用 top 每秒采样 N 秒。
# 用法:scripts/perf/idle-ab.sh <轮数> <采样秒数> "<主题...>" "<条件...>" [标签=idle4]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; P="$ROOT/scripts/perf"
N="${1:-3}"; SECS="${2:-20}"; THEMES="${3:-glass bento}"; CONDS="${4:-step1:fresh:overview step3:alive:overview}"; TAG="${5:-idle4}"
OUT="$ROOT/docs/perf/raw"
echo "cond theme run avg% peak% median% rss_before_MB rss_after_MB top_MEM | 采样前 | 采样后"
for i in $(seq 1 "$N"); do
  for theme in $THEMES; do
    for cond in $CONDS; do
      IFS=: read -r v mode route <<< "$cond"
      BIN="$ROOT/build-$v/MCP Mac.app/Contents/MacOS/MCPMac"
      log="/tmp/$TAG-$v-$mode-$route-$theme-$i.stderr.txt"
      case "$mode" in
        alive)  MCPMAC_SWITCH_BENCH=1 MCPMAC_SWITCH_STAY="$route" MCPMAC_SWITCH_MODE=forced "$BIN" -appearance.theme "$theme" > /dev/null 2> "$log" & ;;
        closed) MCPMAC_CLOSE_TEST=1 MCPMAC_START_ROUTE="$route" "$BIN" -appearance.theme "$theme" > /dev/null 2> "$log" & ;;
        *)      MCPMAC_START_ROUTE="$route" "$BIN" -appearance.theme "$theme" > /dev/null 2> "$log" & ;;
      esac
      pid=$!; t0=$(date +%s)
      if [ "$mode" != closed ]; then sleep 2; osascript -l JavaScript "$P/winstate.js" "$pid" activate > /dev/null 2>&1; fi
      if [ "$mode" = alive ]; then for _ in $(seq 1 80); do grep -aq "staying" "$log" && break; sleep 0.5; done; fi
      while [ $(( $(date +%s) - t0 )) -lt 25 ]; do sleep 0.5; done
      if [ "$mode" != closed ]; then osascript -l JavaScript "$P/winstate.js" "$pid" activate > /dev/null 2>&1; fi
      sleep 1
      before="$(osascript -l JavaScript "$P/winstate.js" "$pid" 2>&1 | cut -d' ' -f1,2)"
      rss0=$(ps -o rss= -p "$pid" | tr -d ' ')
      f="$OUT/$TAG-$v-$mode-$route-$theme-$i.txt"
      top -l $((SECS + 1)) -s 1 -pid "$pid" -stats cpu | awk '/^%CPU/{getline; print $1}' | tail -n "$SECS" > "$f"
      rss1=$(ps -o rss= -p "$pid" | tr -d ' ')
      mem=$(top -l 1 -pid "$pid" -stats mem | tail -1 | tr -d ' ')
      after="$(osascript -l JavaScript "$P/winstate.js" "$pid" 2>&1 | cut -d' ' -f1,2)"
      kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      med=$(sort -n "$f" | awk '{a[NR]=$1} END{print (NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2}')
      awk -v p="$cond $theme $i" -v r0="$rss0" -v r1="$rss1" -v mem="$mem" -v med="$med" '{s+=$1; if($1>m)m=$1} END{printf "%s %.1f %.1f %.1f %.0f %.0f %s", p, s/NR, m, med, r0/1024, r1/1024, mem}' "$f"
      echo " | $before | $after"
      sleep 1
    done
  done
done
echo ALL-DONE
