#!/bin/bash
# 全部页面访问过后停在概览页,用 lldb 数一数窗口视图树里有多少视图、其中有没有"不可见"的子树(隐藏页如果还在窗口里就会出现在这里)。
# 用法:scripts/perf/hidden-roots.sh <副本名> <主题> <输出文件>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; P="$ROOT/scripts/perf"
V="$1"; THEME="$2"; OUTF="$3"
BIN="$ROOT/build-$V/MCP Mac.app/Contents/MacOS/MCPMac"; log="/tmp/hr-$V-$THEME.stderr.txt"
MCPMAC_SWITCH_BENCH=1 MCPMAC_SWITCH_STAY=1 MCPMAC_SWITCH_MODE=forced MCPMAC_SWITCH_COUNT=5 "$BIN" -appearance.theme "$THEME" > /dev/null 2> "$log" &
pid=$!
sleep 2; osascript -l JavaScript "$P/winstate.js" "$pid" activate > /dev/null 2>&1
for _ in $(seq 1 60); do grep -aq staying "$log" && break; sleep 0.5; done
sleep 3
lldb -p "$pid" --batch -s "$P/hidden-roots.lldb" > "/tmp/hr-$V-$THEME.lldb.txt" 2>&1
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
grep -aE "^invisible root|^total" "/tmp/hr-$V-$THEME.lldb.txt" > "$OUTF"
echo "$V $THEME: $(grep -a '^total' "$OUTF")"
awk '/^invisible root/{split($0,a,"descendants="); split(a[2],b," "); if (b[1]+0 >= 30) print}' "$OUTF" | cut -c1-200
