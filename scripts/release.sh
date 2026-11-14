#!/bin/bash
# 发一个版本：测试 → 打包 → 做 DMG → 签名 → 写 appcast.xml；加 PUBLISH=1 就发到 GitHub Release 并推送 appcast。
#
#   scripts/release.sh                              只在本地做出 DMG 和 appcast，不发布
#   PUBLISH=1 NOTES=notes.md scripts/release.sh     发布（NOTES 是更新说明，Markdown，和 GitHub Release 页面同一份）
#
# 发版前改仓库根目录的 VERSION（给人看的版本号）。构建号用提交数，自动递增。
#
# 签名用的 EdDSA 私钥在发版人 Mac 的钥匙串里（Sparkle 的 generate_keys --account mcp-station 生成），
# App 里带着对应的公钥（build-app.sh 的 ED_PUBLIC_KEY）。要在图形界面的终端里跑：SSH 会话读不了钥匙串。
#
# 现在是 ad-hoc 签名、没有公证（公证要付费开发者账号的 Developer ID 证书）：从网上下载的第一次打开会被拦，
# 到「系统设置 → 隐私与安全性」点「仍要打开」；之后的自动更新由 Sparkle 处理，不受影响。
# 更新源要能匿名访问：仓库必须是公开的（raw.githubusercontent.com 读 appcast，Release 下载 DMG）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="yinminqian/mcp-station"
APP="$ROOT/build/MCP Station.app"
DMG="$ROOT/build/MCP-Station.dmg"
APPCAST="$ROOT/appcast.xml"
SPARKLE_BIN="$ROOT/app/.build/artifacts/sparkle/Sparkle/bin"

echo "==> 测试"
(cd "$ROOT/app" && swift test -q)
(cd "$ROOT/core" && cargo test -q)

echo "==> 打包"
"$ROOT/scripts/build-app.sh"
INFO="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")"
MIN_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")"
TAG="v${VERSION}"

# Sparkle 比较的是构建号：不比已发布的大，谁也收不到这个版本。
if [ -f "${APPCAST}" ]; then
    PUBLISHED="$(sed -n 's:.*<sparkle\:version>\(.*\)</sparkle\:version>.*:\1:p' "${APPCAST}" | head -1)"
    if [ -n "${PUBLISHED}" ] && [ "${BUILD_NUMBER}" -le "${PUBLISHED}" ]; then
        echo "!! 构建号 ${BUILD_NUMBER} 不比已发布的 ${PUBLISHED} 大（先提交再发版）"; exit 1
    fi
fi

echo "==> 做 DMG（${VERSION}，构建 ${BUILD_NUMBER}）"
STAGE="$ROOT/build/dmg"
rm -rf "$STAGE" "${DMG}"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/MCP Station.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MCP Station" -srcfolder "$STAGE" -ov -format UDZO "${DMG}" >/dev/null
rm -rf "$STAGE"

echo "==> 签名（钥匙串里的 mcp-station 私钥）"
SIGNED="$("$SPARKLE_BIN/sign_update" --account mcp-station "${DMG}")"
SIGNATURE="$(printf '%s' "${SIGNED}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(printf '%s' "${SIGNED}" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
[ -n "$SIGNATURE" ] && [ -n "$LENGTH" ] || { echo "!! sign_update 没给出签名：${SIGNED}"; exit 1; }

python3 "$ROOT/scripts/appcast.py" "${APPCAST}" "${VERSION}" "${BUILD_NUMBER}" "$MIN_SYSTEM" \
    "https://github.com/${REPO}/releases/download/${TAG}/MCP-Station.dmg" "$SIGNATURE" "$LENGTH" ${NOTES:+"${NOTES}"}
echo "==> 写好了 ${APPCAST}"

if [ "${PUBLISH:-0}" != "1" ]; then
    echo "    没有发布。PUBLISH=1 NOTES=notes.md scripts/release.sh 发布 ${TAG}。"
    exit 0
fi

[ -n "${NOTES:-}" ] && [ -f "${NOTES}" ] || { echo "!! 发布要给 NOTES=更新说明.md"; exit 1; }
gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1 && { echo "!! ${TAG} 已经发过了（改 VERSION）"; exit 1; }
# 从 main 发：打包的内容必须就是 main 上的
git -C "$ROOT" fetch -q origin main
[ "$(git -C "$ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse origin/main)" ] || { echo "!! HEAD 不是 origin/main，先推送"; exit 1; }
[ -z "$(git -C "$ROOT" status --porcelain -- . ':!appcast.xml')" ] || { echo "!! 有没提交的改动，DMG 会和标签对不上"; exit 1; }

echo "==> 发布 ${TAG}"
# 先传安装包、后推更新源：更新源永远不会指向还不存在的包
gh release create "${TAG}" "${DMG}" --repo "${REPO}" --target main --title "MCP Station ${VERSION}" --notes-file "${NOTES}"
git -C "$ROOT" add appcast.xml
git -C "$ROOT" commit -q -m "更新源：提供 ${VERSION}"
git -C "$ROOT" push -q origin main
echo "==> 发布了 ${TAG}；装着旧版的 App 下次启动会收到提示"
