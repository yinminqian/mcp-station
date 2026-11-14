#!/bin/bash
# 版面自截图:用 App 自带的 MCPSTATION_SNAPSHOT_DIR 模式给若干副本各截一套(两套主题 × 5 页 + 后台服务没运行)。
# 这个模式会往 UserDefaults 里写主题,为了不影响正在运行的其他 MCP Station 实例,
# 这里把 .app 拷到临时目录并把 bundle id 改成 com.example.mcp-station.snap(只改 Info.plist,可执行文件不动),测完删掉那个域。
# 用法:scripts/perf/snapshots.sh "<副本名...>" [临时目录=/tmp/mcpstation-perf4]     输出 docs/perf/raw/snap-<副本>/*.png(缩到宽 1180)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VARIANTS="${1:-step2 step3}"; TMP="${2:-/tmp/mcpstation-perf4}"
for v in $VARIANTS; do
  app="$TMP/snapapp-$v/MCP Station.app"
  rm -rf "$TMP/snapapp-$v"; mkdir -p "$TMP/snapapp-$v"
  ditto "$ROOT/build-$v/MCP Station.app" "$app"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.example.mcp-station.snap" "$app/Contents/Info.plist"
  echo "$v binary sha256: $(shasum -a 256 "$app/Contents/MacOS/MCPStation" | cut -c1-16) (应与冻结副本相同)"
  out="$ROOT/docs/perf/raw/snap-$v"; rm -rf "$out"; mkdir -p "$out"
  MCPSTATION_SNAPSHOT_DIR="$out" "$app/Contents/MacOS/MCPStation" > "$TMP/snap-$v.log" 2>&1
  echo "$v exit $? files: $(ls "$out" | wc -l | tr -d ' ')"
  for f in "$out"/*.png; do sips -Z 1180 "$f" > /dev/null 2>&1; done
  ls -la "$out" | awk 'NR>1{print $5, $9}'
  defaults delete com.example.mcp-station.snap > /dev/null 2>&1
done
defaults read com.example.mcp-station appearance.theme 2>&1 | tail -1
