#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/scripts/toolchain.sh"
mkdir -p "$ROOT/.build/tests"
echo "==> 计数引擎回归（口径、人工佐证、预算、基线回收、按键分类）"
xcrun swiftc -sdk "$KEYCOUNT_BUILD_SDK" -target "$KEYCOUNT_TARGET" \
    -swift-version 5 -parse-as-library \
    "$ROOT/Sources/KeyCount/CountingEngine.swift" \
    "$ROOT/Sources/KeyCount/TypingActivity.swift" \
    "$ROOT/Tests/CountingTests.swift" \
    -o "$ROOT/.build/tests/counting-tests"
"$ROOT/.build/tests/counting-tests"
echo "==> 界面数据、进度、图表与偏好设置"
xcrun swiftc -sdk "$KEYCOUNT_BUILD_SDK" -target "$KEYCOUNT_TARGET" \
    -swift-version 5 -parse-as-library \
    "$ROOT/Sources/KeyCount/HistoryStore.swift" \
    "$ROOT/Sources/KeyCount/DashboardModel.swift" \
    "$ROOT/Sources/KeyCount/PermissionPolicy.swift" \
    "$ROOT/Sources/KeyCount/AppPreferences.swift" \
    "$ROOT/Tests/DashboardTests.swift" \
    -o "$ROOT/.build/tests/dashboard-tests"
"$ROOT/.build/tests/dashboard-tests"
echo "==> 授权请求与监听生命周期（模拟，无系统弹窗）"
xcrun swiftc -sdk "$KEYCOUNT_BUILD_SDK" -target "$KEYCOUNT_TARGET" \
    -swift-version 5 -parse-as-library \
    "$ROOT/Sources/KeyCount/PermissionPolicy.swift" \
    "$ROOT/Tests/PermissionTests.swift" \
    -o "$ROOT/.build/tests/permission-tests"
"$ROOT/.build/tests/permission-tests"
echo "==> 所有源码类型检查"
xcrun swiftc -sdk "$KEYCOUNT_BUILD_SDK" -target "$KEYCOUNT_TARGET" \
    -swift-version 5 -parse-as-library -typecheck "$ROOT"/Sources/KeyCount/*.swift
echo "==> 脚本和 plist 校验"
for script in "$ROOT"/*.sh "$ROOT"/scripts/*.sh; do bash -n "$script"; done
plutil -lint "$ROOT/Resources/Info.plist"
