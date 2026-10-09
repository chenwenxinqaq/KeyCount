#!/usr/bin/env bash
# Build + bundle + sign in the workspace only. No install, launch or permissions.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/scripts/toolchain.sh"
BUILD="$ROOT/.build/local"
mkdir -p "$BUILD"

case "${1:-}" in
    ""|--direct) ;;
    *) echo "用法: ./build.sh [--direct]"; exit 2 ;;
esac

echo "==> SDK: $KEYCOUNT_BUILD_SDK"
echo "==> 构建 $KEYCOUNT_TARGET"
DIRECT=0
[[ "${1:-}" == "--direct" ]] && DIRECT=1
if [[ "$DIRECT" == 0 ]]; then
    if SDKROOT="$KEYCOUNT_BUILD_SDK" swift build --package-path "$ROOT" \
        --sdk "$KEYCOUNT_BUILD_SDK" -c release >"$BUILD/swift-build.log" 2>&1; then
        BIN_DIR="$(SDKROOT="$KEYCOUNT_BUILD_SDK" swift build --package-path "$ROOT" \
            --sdk "$KEYCOUNT_BUILD_SDK" -c release --show-bin-path)"
        cp "$BIN_DIR/KeyCount" "$BUILD/KeyCount"
    elif grep -q 'Invalid manifest' "$BUILD/swift-build.log" \
        && grep -q 'PackageDescription' "$BUILD/swift-build.log"; then
        echo "    SwiftPM manifest 工具链不匹配，改用项目内直接编译（不修改系统）。"
        DIRECT=1
    else
        cat "$BUILD/swift-build.log" >&2
        exit 1
    fi
fi

if [[ "$DIRECT" == 1 ]]; then
    # No external packages or SwiftPM-generated resources in this target.
    xcrun swiftc -sdk "$KEYCOUNT_BUILD_SDK" -target "$KEYCOUNT_TARGET" \
        -swift-version 5 -O -parse-as-library -module-name KeyCount \
        "$ROOT"/Sources/KeyCount/*.swift -o "$BUILD/KeyCount"
fi

echo "==> 打包应用图标"
if [[ ! -f "$ROOT/Resources/AppIcon.icns" || ! -f "$ROOT/Resources/AppIcon.png" \
    || "$ROOT/scripts/make_icons.swift" -nt "$ROOT/Resources/AppIcon.icns" ]]; then
    xcrun swift -sdk "$KEYCOUNT_BUILD_SDK" "$ROOT/scripts/make_icons.swift" \
        "$BUILD/icons"
    iconutil -c icns "$BUILD/icons/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
    cp "$BUILD/icons/AppIcon.png" "$ROOT/Resources/AppIcon.png"
fi

STAGE="$(mktemp -d "$BUILD/bundle.XXXXXX")"
trap 'if [[ -n "${STAGE:-}" && -d "$STAGE" ]]; then rm -rf "$STAGE"; fi' EXIT
APP="$STAGE/KeyCount.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/KeyCount" "$APP/Contents/MacOS/KeyCount"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$ROOT/Resources/AppIcon.png" "$APP/Contents/Resources/"
plutil -lint "$APP/Contents/Info.plist"

# 签名身份选择（从不自动导入私钥；只使用已就绪的身份）：
#   1. 显式 KEYCOUNT_SIGN_ID（如 Developer ID）优先；
#   2. 否则用固定自签名身份（scripts/import_signing_cert.sh 导入到专用钥匙串）——
#      它让 designated requirement 绑定证书而非 cdhash，TCC 授权跨版本保留；
#   3. 都没有则回退 ad-hoc（每次构建身份都变，更新后需重新授权）。
LOCAL_IDENTITY="KeyCount Dev"
SIGNING_KEYCHAIN="${KEYCOUNT_KEYCHAIN:-$HOME/Library/Keychains/keycount-signing.keychain-db}"
SIGNING_KEYCHAIN_PW="${KEYCOUNT_KEYCHAIN_PW:-keycount-local-signing}"
SIGN_ID="${KEYCOUNT_SIGN_ID:-}"
if [[ -z "$SIGN_ID" ]]; then
    if [[ -f "$SIGNING_KEYCHAIN" ]] \
        && security find-identity -p codesigning "$SIGNING_KEYCHAIN" 2>/dev/null \
            | grep -q "$LOCAL_IDENTITY"; then
        security unlock-keychain -p "$SIGNING_KEYCHAIN_PW" "$SIGNING_KEYCHAIN" 2>/dev/null || true
        if ! security list-keychains -d user | sed 's/"//g' | grep -qF "$SIGNING_KEYCHAIN"; then
            KEYCHAINS="$(security list-keychains -d user | sed 's/"//g' | xargs)"
            # shellcheck disable=SC2086
            security list-keychains -d user -s $KEYCHAINS "$SIGNING_KEYCHAIN"
        fi
        SIGN_ID="$LOCAL_IDENTITY"
    else
        SIGN_ID="-"
    fi
fi
case "$SIGN_ID" in
    "-")
        echo "==> 本地 ad-hoc 签名"
        codesign --force --sign - "$APP" ;;
    "$LOCAL_IDENTITY")
        echo "==> 固定自签名身份：$LOCAL_IDENTITY"
        codesign --force --sign "$LOCAL_IDENTITY" "$APP" ;;
    *)
        echo "==> 使用指定身份签名"
        codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP" ;;
esac
codesign --verify --strict "$APP"

if [[ -e "$ROOT/KeyCount.app" ]]; then
    BACKUP="$(mktemp -d "$BUILD/previous.XXXXXX")"
    mv "$ROOT/KeyCount.app" "$BACKUP/"
fi
mv "$APP" "$ROOT/KeyCount.app"
echo "✅ 已构建：$ROOT/KeyCount.app"
echo "   仅生成工作区产物，未安装、未启动。"
case "$SIGN_ID" in
    "-")
        echo "⚠️  这是 ad-hoc 临时签名，更换构建后可能需要重新授权。"
        echo "    运行 ./scripts/import_signing_cert.sh 可改用固定自签名身份，授权不再丢失。"
        echo "    运行 ./make_dmg.sh --local 可生成未公证 DMG；Developer ID 与公证可后续配置。" ;;
    "$LOCAL_IDENTITY")
        echo "🔏 已用固定自签名身份签名：designated requirement 绑定证书，TCC 授权可跨版本保留。"
        echo "    自签名未公证：首次打开仍需右键→打开，仅适合本机自用。"
        echo "    测试打包请显式运行 ./make_dmg.sh --local。" ;;
esac
