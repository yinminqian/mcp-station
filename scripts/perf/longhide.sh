#!/bin/bash
# 隐藏很久后切回:calls ↔ overview 来回切,每次停留 60 秒,全程 Time Profiler 录制。
# 切到最后停在 calls(MCPMAC_SWITCH_STAY=calls),"staying" 一出现就用 lldb 给窗口截图,核对表格第一行是不是刚刚的数据。
# 每次切页前 4 秒把窗口重新激活到前台(用户在用机器时窗口会被盖住)。
# 用法:scripts/perf/longhide.sh <副本名=step3> "<主题...>" <输出目录=/tmp/mcpmac-perf4> [切页次数=5] [停留毫秒=60000]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; P="$ROOT/scripts/perf"
V="${1:-step3}"; THEMES="${2:-glass bento}"; OUT="${3:-/tmp/mcpmac-perf4}"; COUNT="${4:-5}"; DWELL="${5:-60000}"
BIN="$ROOT/build-$V/MCP Mac.app/Contents/MacOS/MCPMac"
RAW="$ROOT/docs/perf/raw"
mkdir -p "$OUT"; cd "$OUT"
for theme in $THEMES; do
  t="longhide-$V-$theme"
  rm -rf "$t.trace" "$t.stdout.txt" "$t.winstate.txt"
  LIMIT=$(( 8 + (COUNT - 1) * DWELL / 1000 + 14 ))
  ( pid=""; for _ in $(seq 1 80); do pid=$(pgrep -f "^$BIN" | head -1); [ -n "$pid" ] && break; sleep 0.25; done
    t0=$(date +%s)
    sleep 1.5; osascript -l JavaScript "$P/winstate.js" "$pid" activate > /dev/null 2>&1
    for k in $(seq 1 $((COUNT - 1))); do
      target=$(( t0 + 5 + k * DWELL / 1000 - 4 ))
      while [ "$(date +%s)" -lt "$target" ]; do sleep 0.5; done
      echo "before switch $((k + 1)): $(osascript -l JavaScript "$P/winstate.js" "$pid" activate 2>&1 | cut -d' ' -f1,2)" >> "$t.winstate.txt"
    done
    # 最后一次切页完成("staying")后立刻截图
    for _ in $(seq 1 120); do grep -aq "staying" "$t.stdout.txt" 2>/dev/null && break; sleep 0.25; done
    echo "staying seen at $(date +%H:%M:%S)" >> "$t.winstate.txt"
    png="$RAW/step3-longhide-$theme-calls-after-60s.png"
    sed "s|__PNG__|$png|" "$P/snapshot.lldb" > "$t.snapshot.lldb"
    lldb -p "$pid" --batch -s "$t.snapshot.lldb" > "$t.lldb.txt" 2>&1
    echo "snapshot done at $(date +%H:%M:%S): $(ls -la "$png" 2>&1 | awk '{print $5}') bytes" >> "$t.winstate.txt" ) &
  xcrun xctrace record --template 'Time Profiler' --output "$t.trace" --time-limit "${LIMIT}s" \
    --env MCPMAC_SWITCH_BENCH=1 --env MCPMAC_SWITCH_MODE=forced --env MCPMAC_SWITCH_ROUTES=calls,overview \
    --env MCPMAC_SWITCH_DWELL_MS="$DWELL" --env MCPMAC_SWITCH_COUNT="$COUNT" --env MCPMAC_SWITCH_STAY=calls \
    --target-stdout "$t.stdout.txt" --launch -- "$BIN" -appearance.theme "$theme" > "$t.rec.log" 2>&1
  wait
  pkill -f "^$BIN" 2>/dev/null
  for s in runloop-events time-profile; do
    xcrun xctrace export --input "$t.trace" --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$s\"]" > "$t.$s.xml" 2>/dev/null
  done
  python3 "$P/xctrace_rows.py" "$t.runloop-events.xml" "$t.runloop.tsv"
  python3 "$P/tp_dump.py" "$t.time-profile.xml" "$t.samples.tsv"
  rm -f "$t.runloop-events.xml" "$t.time-profile.xml"
  echo "== $t  load: $(uptime | sed 's/.*load averages: //')"
  grep -a '^bench' "$t.stdout.txt"; cat "$t.winstate.txt"
done
echo LONGHIDE-DONE
