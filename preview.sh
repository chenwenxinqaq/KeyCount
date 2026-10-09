#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/scripts/toolchain.sh"
mkdir -p "$ROOT/.build/previews" "$ROOT/dist/previews"
SOURCES=()
for source in "$ROOT"/Sources/KeyCount/*.swift; do
    [[ "$(basename "$source")" == KeyCountApp.swift ]] || SOURCES+=("$source")
done
xcrun swiftc -sdk "$KEYCOUNT_BUILD_SDK" -target "$KEYCOUNT_TARGET" \
    -swift-version 5 -parse-as-library "${SOURCES[@]}" \
    "$ROOT/scripts/render_previews.swift" -o "$ROOT/.build/previews/render"
KEYCOUNT_PREVIEW_RESOURCES="$ROOT/Resources" "$ROOT/.build/previews/render" "$ROOT/dist/previews"
echo "预览使用模拟数据，未启动监控或修改真实统计。"
