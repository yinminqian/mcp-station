#!/bin/bash
# 组装 MCP Station.app（内核 mcp-core + SwiftPM 产物 → .app bundle → ad-hoc 签名）。
#
# 用法：
#   scripts/build-app.sh            release 构建，产物在 build/MCP Station.app
#   scripts/build-app.sh --debug    debug 构建（编译快，调试用）
#   scripts/build-app.sh --install  构建后安装到 /Applications（已存在则先退出旧进程再覆盖）
#   scripts/build-app.sh --install-core  再用包里的内核升级 / 重启正在跑的内核（客户端会断几秒）
#
# 内核放在 App 包的 Contents/Resources/mcp-core；App 发现内核没装会自动装（复制到数据目录、写 LaunchAgent）。
# 重装 App 不会打断正在跑的内核（它跑的是数据目录里的那份），要升级内核加 --install-core 或在 App 里点「重启」。
#
# v1 只做 ad-hoc 签名（codesign -s -），不用证书；以后用用户本人账号签名时只改 SIGN_ID。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MCP Station"
BUNDLE_ID="com.example.mcp-station"
SIGN_ID="-"
CONFIG=release
INSTALL=0
INSTALL_CORE=0
for a in "$@"; do
  case "$a" in
    --debug) CONFIG=debug ;;
    --install) INSTALL=1 ;;
    --install-core) INSTALL_CORE=1 ;;
    *) echo "未知参数 $a" >&2; exit 2 ;;
  esac
done

# 内核（Rust）。release 用全局优化，第一次编要几分钟，之后增量很快。
# 版本号：VERSION 文件（给人看的，发版时改）；构建号用提交数（只增不减，Sparkle 靠它判断新旧，不用手动改）
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
# 自动更新（Sparkle）：更新源是仓库里的 appcast.xml，安装包是 GitHub Release 上的 DMG，用这个公钥验签。
# 私钥在发版人的钥匙串里（generate_keys --account mcp-station），见 scripts/release.sh。
FEED_URL="https://raw.githubusercontent.com/yinminqian/mcp-station/main/appcast.xml"
ED_PUBLIC_KEY="CVNnvpXpZeLXjOOkQk5AqWv/KhJWbESzxSg2BiDafpg="

# 在 core 目录里编：cargo 只从当前目录往上找 .cargo/config.toml（本机可以在那里配 crates 镜像）
(cd "$ROOT/core" && MCPSTATION_VERSION="$VERSION" cargo build --release)
CORE_BIN="$ROOT/core/target/release/mcp-core"

cd "$ROOT/app"
swift build -c "$CONFIG" --product MCPStation
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MCPStation"

OUT="$ROOT/build/$APP_NAME.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$OUT/Contents/Frameworks"
cp "$BIN" "$OUT/Contents/MacOS/MCPStation"
cp "$CORE_BIN" "$OUT/Contents/Resources/mcp-core"
# Sparkle 是动态框架，放进 Frameworks，并让可执行文件去那里找
ditto "$(swift build -c "$CONFIG" --show-bin-path)/Sparkle.framework" "$OUT/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$OUT/Contents/MacOS/MCPStation" 2>/dev/null || true
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>MCPStation</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$ED_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>172800</integer>
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

# 包里的可执行文件和框架先单独签，再签整个包
codesign --force --sign "$SIGN_ID" --timestamp=none "$OUT/Contents/Resources/mcp-core"
codesign --force --deep --sign "$SIGN_ID" --timestamp=none "$OUT/Contents/Frameworks/Sparkle.framework"
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

if [ "$INSTALL_CORE" = 1 ]; then
  "$OUT/Contents/Resources/mcp-core" install --restart
fi
