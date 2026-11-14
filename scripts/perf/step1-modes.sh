#!/bin/bash
# 第 1 步副本:natural 与 forced 两种计时模式交替各跑 N 轮(不挂 Instruments),原始输出存 docs/perf/raw/。
# 用法:scripts/perf/step1-modes.sh [轮数=3]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/build-step1/MCP Mac.app/Contents/MacOS/MCPMac"
OUT="$ROOT/docs/perf/raw"; N="${1:-3}"
for i in $(seq 1 "$N"); do
  for mode in natural forced; do
    f="$OUT/step1-$mode-$i.txt"
    MCPMAC_SWITCH_BENCH=1 MCPMAC_SWITCH_MODE="$mode" "$BIN" -appearance.theme glass 2>&1 | grep -a '^bench' > "$f"
    echo "== $mode $i (exit ${PIPESTATUS[0]})  load: $(uptime | sed 's/.*load averages: //')"; cat "$f"
    sleep 2
  done
done
echo ALL-DONE
