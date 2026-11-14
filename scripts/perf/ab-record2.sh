#!/bin/bash
# 背靠背对比(通用版):若干冻结副本 × 若干主题,交替用 Time Profiler 模板录全程 bench(forced 模式)。
# 每次录制都在目标进程出现 1.5 秒后把窗口激活到前台,保证各副本窗口状态一致(窗口不在屏时会多出软件光栅化)。
# 用法:scripts/perf/ab-record2.sh <轮数> <输出目录> <起始轮号> "<副本名...>" "<主题...>"
#   例:scripts/perf/ab-record2.sh 3 /tmp/mcpstation-perf3 1 "step1 step2" "glass bento"
# 产出:<目录>/tp-<副本>-<主题>-<轮>.{trace,stdout.txt,runloop.tsv,samples.tsv,winstate.txt}
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
P="$ROOT/scripts/perf"
N="${1:-3}"; OUT="${2:-/tmp/mcpstation-perf3}"; FROM="${3:-1}"; VARIANTS="${4:-step1 step2}"; THEMES="${5:-glass bento}"
mkdir -p "$OUT"; cd "$OUT"
for i in $(seq "$FROM" $((FROM + N - 1))); do
  for theme in $THEMES; do
    for v in $VARIANTS; do
      BIN="$ROOT/build-$v/MCP Station.app/Contents/MacOS/MCPStation"
      t="tp-$v-$theme-$i"
      rm -rf "$t.trace"
      ( pid=""; for _ in $(seq 1 60); do pid=$(pgrep -f "^$BIN" | head -1); [ -n "$pid" ] && break; sleep 0.25; done
        sleep 1.5
        osascript -l JavaScript "$P/winstate.js" "$pid" activate > /dev/null 2>&1
        sleep 6; echo "mid-run: $(osascript -l JavaScript "$P/winstate.js" "$pid" 2>&1)" > "$t.winstate.txt" ) &
      xcrun xctrace record --template 'Time Profiler' --output "$t.trace" \
        --env MCPSTATION_SWITCH_BENCH=1 --env MCPSTATION_SWITCH_MODE=forced \
        --target-stdout "$t.stdout.txt" --launch -- "$BIN" -appearance.theme "$theme" > "$t.rec.log" 2>&1
      wait
      for s in runloop-events time-profile; do
        xcrun xctrace export --input "$t.trace" --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$s\"]" > "$t.$s.xml" 2>/dev/null
      done
      python3 "$P/xctrace_rows.py" "$t.runloop-events.xml" "$t.runloop.tsv"
      python3 "$P/tp_dump.py" "$t.time-profile.xml" "$t.samples.tsv"
      rm -f "$t.runloop-events.xml" "$t.time-profile.xml"
      echo "== $t  load: $(uptime | sed 's/.*load averages: //')  $(cut -d' ' -f2-4 "$t.winstate.txt" 2>/dev/null)"
      grep -a '^bench' "$t.stdout.txt"
      sleep 2
    done
  done
done
echo ALL-DONE
