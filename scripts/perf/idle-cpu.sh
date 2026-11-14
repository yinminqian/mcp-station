#!/bin/bash
# 空闲 CPU:两套主题 × 5 个页面,各停留 N 秒,用 top 每秒采样一次,输出平均和峰值。
# 主题走参数域(-appearance.theme),页面走 MCPMAC_START_ROUTE;不写持久 defaults。
# 用法:scripts/perf/idle-cpu.sh [停留秒数=20] [预热秒数=6] [activate|background] [标签=同第三个参数]
#   activate   启动后把 App 激活到前台(窗口在屏、可见)——这才是用户实际看到的状态
#   background 不激活(从后台 shell 启动时窗口不在当前屏幕上,系统会降低它的刷新)
# 可用环境变量 THEMES="glass" ROUTES="overview calls" 只测一部分。
# 原始采样存 docs/perf/raw/idle-<标签>-<theme>-<route>.txt
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/build/MCP Mac.app/Contents/MacOS/MCPMac"
OUT="$ROOT/docs/perf/raw"
SECS="${1:-20}"; WARM="${2:-6}"; MODE="${3:-activate}"; TAG="${4:-$MODE}"
mkdir -p "$OUT"
echo "mode theme route avg% peak% min% | 采样前窗口状态 | 采样后窗口状态"
for theme in ${THEMES:-glass bento}; do
  for route in ${ROUTES:-overview mcps services calls settings}; do
    MCPMAC_START_ROUTE="$route" "$BIN" -appearance.theme "$theme" >/dev/null 2>&1 &
    pid=$!
    sleep 2
    if [ "$MODE" = activate ]; then osascript -l JavaScript "$ROOT/scripts/perf/winstate.js" "$pid" activate >/dev/null 2>&1; fi
    sleep "$WARM"
    before="$(osascript -l JavaScript "$ROOT/scripts/perf/winstate.js" "$pid" 2>&1 | cut -d' ' -f1,2)"
    f="$OUT/idle-$TAG-$theme-$route.txt"
    # top 的第一拍没有增量(恒为 0),丢掉
    top -l $((SECS + 1)) -s 1 -pid "$pid" -stats cpu | awk '/^%CPU/{getline; print $1}' | tail -n "$SECS" > "$f"
    after="$(osascript -l JavaScript "$ROOT/scripts/perf/winstate.js" "$pid" 2>&1 | cut -d' ' -f1,2)"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    awk -v p="$MODE $theme $route" '{s+=$1; if($1>m)m=$1; if(NR==1||$1<mn)mn=$1} END{printf "%s %.1f %.1f %.1f", p, s/NR, m, mn}' "$f"
    echo " | $before | $after"
    sleep 1
  done
done
