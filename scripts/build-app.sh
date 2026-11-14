#!/bin/bash
# 组装 MCP Mac.app（SwiftPM 产物 → .app bundle → ad-hoc 签名）。
#
# 用法：
#   scripts/build-app.sh            release 构建，产物在 build/MCP Mac.app
#   scripts/build-app.sh --debug    debug 构建（编译快，调试用）
#   scripts/build-app.sh --install  构建后安装到 /Applications（已存在则先退出旧进程再覆盖）
#
# v1 只做 ad-hoc 签名（codesign -s -），不用证书；以后用用户本人账号签名时只改 SIGN_ID。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MCP Mac"
BUNDLE_ID="com.example.mcp-mac"
SIGN_ID="-"
CONFIG=release
INSTALL=0
for a in "$@"; do
  case "$a" in
    --debug) CONFIG=debug ;;
    --install) INSTALL=1 ;;
    *) echo "未知参数 $a" >&2; exit 2 ;;
  esac
done

cd "$ROOT/app"
swift build -c "$CONFIG" --product MCPMac
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MCPMac"

OUT="$ROOT/build/$APP_NAME.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/MCPMac"

VERSION="$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo 0.1.0)"
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>MCPMac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

if [ -f "$ROOT/app/Resources/AppIcon.icns" ]; then
  cp "$ROOT/app/Resources/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$OUT/Contents/Info.plist"
fi

codesign --force --sign "$SIGN_ID" --timestamp=none "$OUT"
echo "已构建：${OUT}（${CONFIG}）"

if [ "$INSTALL" = 1 ]; then
  DEST="/Applications/$APP_NAME.app"
  if [ -e "$DEST" ]; then
    # 只覆盖我们自己的 bundle，别的同名东西不碰
    existing="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$existing" != "$BUNDLE_ID" ]; then
      echo "${DEST} 已存在且不是本应用（${existing}），不覆盖" >&2; exit 1
    fi
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
    sleep 1
    rm -rf "$DEST"
  fi
  ditto "$OUT" "$DEST"
  echo "已安装：${DEST}"
fi
