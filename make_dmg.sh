#!/usr/bin/env bash
# Package an existing workspace .app; never installs it or touches user data.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$ROOT/KeyCount.app"
DIST_DIR="$ROOT/dist"
MODE="release"
SIGN_ID=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --local) MODE="local" ;;
        --help|-h)
            echo "用法: ./make_dmg.sh [--local | \"Developer ID Application: ...\"]"
            echo "临时签名仅允许 --local 打包，文件名明确标为测试版。"
            exit 0 ;;
        --*) echo "未知参数：$1" >&2; exit 2 ;;
        *)
            if [[ -n "$SIGN_ID" ]]; then echo "只能指定一个签名身份。" >&2; exit 2; fi
            SIGN_ID="$1" ;;
    esac
    shift
done
if [[ "$MODE" == "local" && -n "$SIGN_ID" ]]; then
    echo "--local 不能与正式签名身份一起使用。" >&2
    exit 2
fi
if [[ ! -d "$APP_PATH" ]]; then
    echo "请先运行 ./build.sh 构建 KeyCount.app。" >&2
    exit 1
fi
mkdir -p "$DIST_DIR"
STAGE="$(mktemp -d "$DIST_DIR/.dmg-stage.XXXXXX")"
trap 'if [[ -n "${STAGE:-}" && -d "$STAGE" ]]; then rm -rf "$STAGE"; fi' EXIT
ditto "$APP_PATH" "$STAGE/KeyCount.app"
if [[ -n "$SIGN_ID" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$STAGE/KeyCount.app"
fi
codesign --verify --strict "$STAGE/KeyCount.app"
SIGNING="$(codesign -dv --verbose=4 "$STAGE/KeyCount.app" 2>&1)"
if [[ "$MODE" == "release" ]]; then
    if ! grep -q '^Authority=Developer ID Application:' <<<"$SIGNING" \
        || ! grep -q '^TeamIdentifier=[A-Z0-9]' <<<"$SIGNING"; then
        echo "拒绝将临时签名或非 Developer ID 应用打成正式分发包。" >&2
        echo "请用自己的 Developer ID 构建；仅测试时显式加 --local。" >&2
        exit 1
    fi
    codesign --verify --strict \
        -R='anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' \
        "$STAGE/KeyCount.app"
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$STAGE/KeyCount.app/Contents/Info.plist")"
ARCH="$(lipo -archs "$STAGE/KeyCount.app/Contents/MacOS/KeyCount" | tr ' ' '-')"
SUFFIX=""
[[ "$MODE" == "local" ]] && SUFFIX="-local"
OUT="$DIST_DIR/KeyCount-${VERSION}-${ARCH}${SUFFIX}.dmg"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Resources/安装与授权说明.txt" "$STAGE/安装与授权说明.txt"
# Keep the image output outside the source folder being packaged.
TMP_IMAGE="$(mktemp -d "$DIST_DIR/.dmg-output.XXXXXX")"
trap 'if [[ -d "$STAGE" ]]; then rm -rf "$STAGE"; fi; if [[ -d "$TMP_IMAGE" ]]; then rm -rf "$TMP_IMAGE"; fi' EXIT
hdiutil create -volname "KeyCount $VERSION" -srcfolder "$STAGE" -format UDZO \
    "$TMP_IMAGE/KeyCount.dmg" >/dev/null
if [[ -n "$SIGN_ID" ]]; then
    codesign --force --sign "$SIGN_ID" "$TMP_IMAGE/KeyCount.dmg"
fi
hdiutil verify "$TMP_IMAGE/KeyCount.dmg" >/dev/null
mv "$TMP_IMAGE/KeyCount.dmg" "$OUT"
# Maintain the familiar local shortcut, without leaving the old build behind.
cp "$OUT" "$TMP_IMAGE/KeyCount-latest.dmg"
mv "$TMP_IMAGE/KeyCount-latest.dmg" "$DIST_DIR/KeyCount.dmg"
echo "✅ 已生成：$OUT"
echo "   $DIST_DIR/KeyCount.dmg 也已同步为本次构建。"
if [[ "$MODE" == "local" ]]; then
    if grep -q '^Authority=KeyCount Dev' <<<"$SIGNING"; then
        echo "🔏 本地包，固定自签名身份；授权可跨版本保留，但未公证（首次打开需右键→打开）。"
    else
        echo "⚠️  本地 ad-hoc 测试包，未公证；更换构建后可能需要移除旧权限条目并重新授权。"
        echo "    运行 ./scripts/import_signing_cert.sh 可改用固定自签名身份。"
    fi
else
    echo "公开分发前仍需完成公证与装订；本脚本不自动上传应用。"
fi
