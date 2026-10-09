#!/usr/bin/env bash
# Explicit opt-in install. build.sh alone never installs or launches the app.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="/Applications/KeyCount.app"
RUN_AFTER=1
case "${1:-}" in
    "") ;;
    --no-run) RUN_AFTER=0 ;;
    *) echo "用法: ./install.sh [--no-run]"; exit 2 ;;
esac

"$ROOT/build.sh"
STAGE="$(mktemp -d /Applications/.KeyCount-install.XXXXXX)"
trap 'if [[ -n "${STAGE:-}" && -d "$STAGE" ]]; then rm -rf "$STAGE"; fi' EXIT
ditto "$ROOT/KeyCount.app" "$STAGE/KeyCount.app"
codesign --verify --strict "$STAGE/KeyCount.app"

if pgrep -f '^/Applications/KeyCount.app/Contents/MacOS/KeyCount([[:space:]]|$)' >/dev/null; then
    osascript -e 'tell application id "com.local.keycount" to quit'
    sleep 1
    if pgrep -f '^/Applications/KeyCount.app/Contents/MacOS/KeyCount([[:space:]]|$)' >/dev/null; then
        echo "请先退出正在运行的 KeyCount，再重试安装。" >&2
        exit 1
    fi
fi
if [[ -e "$DEST" ]]; then
    mkdir -p "$ROOT/.build/installed-backups"
    BACKUP="$(mktemp -d "$ROOT/.build/installed-backups/previous.XXXXXX")"
    mv "$DEST" "$BACKUP/"
    echo "旧应用已保留于 $BACKUP"
fi
mv "$STAGE/KeyCount.app" "$DEST"
if [[ "$RUN_AFTER" == 1 ]]; then
    open "$DEST"
    echo "✅ 已安装，并请求启动：$DEST"
else
    echo "✅ 已安装，未启动：$DEST"
fi
echo "首次使用请点菜单栏图标，在面板内开启辅助功能；输入监控可选。"
echo "本地 ad-hoc 签名更新后，系统可能需要重新授权。"
