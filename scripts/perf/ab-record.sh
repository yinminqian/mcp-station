#!/bin/bash
# 背靠背对比:基线 / 第 1 步两个冻结副本交替用 Time Profiler 模板录全程 bench(forced 模式),
# 导出 runloop-events 与 time-profile 并转成 TSV,供 switch_profile.py / ab_summary.py 归因。
# 用法:scripts/perf/ab-record.sh [轮数=3] [输出目录=/tmp/mcpmac-perf2] [起始轮号=1]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
P="$ROOT/scripts/perf"
N="${1:-3}"; OUT="${2:-/tmp/mcpmac-perf2}"; FROM="${3:-1}"
mkdir -p "$OUT"; cd "$OUT"
for i in $(seq "$FROM" $((FROM + N - 1))); do
  for v in baseline step1; do
    BIN="$ROOT/build-$v/MCP Mac.app/Contents/MacOS/MCPMac"
    t="tp-$v-$i"
    rm -rf "$t.trace"
    xcrun xctrace record --template 'Time Profiler' --output "$t.trace" \
      --env MCPMAC_SWITCH_BENCH=1 --env MCPMAC_SWITCH_MODE=forced \
      --target-stdout "$t.stdout.txt" --launch -- "$BIN" -appearance.theme glass > "$t.rec.log" 2>&1
    for s in runloop-events time-profile; do
      xcrun xctrace export --input "$t.trace" --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$s\"]" > "$t.$s.xml" 2>/dev/null
    done
    python3 "$P/xctrace_rows.py" "$t.runloop-events.xml" "$t.runloop.tsv"
    python3 "$P/tp_dump.py" "$t.time-profile.xml" "$t.samples.tsv"
    rm -f "$t.runloop-events.xml" "$t.time-profile.xml"
    echo "== $t  load: $(uptime | sed 's/.*load averages: //')"
    grep -a '^bench' "$t.stdout.txt"
    sleep 2
  done
done
echo ALL-DONE
