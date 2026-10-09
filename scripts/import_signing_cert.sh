#!/usr/bin/env bash
# One-time: put the project's self-signed signing identity into a dedicated
# keychain so every build signs with a STABLE identity.
#
# Why: macOS TCC (Accessibility / Input Monitoring) keys its grants to an app's
# code-signing *designated requirement*. Ad-hoc signing (codesign -s -) builds
# that requirement from the binary's cdhash, which changes on every rebuild, so
# each update looks like a brand-new app and loses authorization. Signing with a
# fixed certificate makes the requirement reference that certificate instead
# (`certificate leaf = H"..."`), so grants persist across rebuilds.
#
# A dedicated keychain (not the login keychain) lets us authorize codesign to
# use the key non-interactively via set-key-partition-list, using a password we
# control. The certificate and private key are expected to exist only in the
# local, git-ignored certs/ directory. This identity is self-signed, for local
# use on your own machine only (not notarized; first launch still needs
# right-click -> Open). Re-running this script is safe (idempotent).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT="$ROOT/certs/cert.pem"
KEY="$ROOT/certs/key.pem"
IDENTITY_CN="KeyCount Dev"
KEYCHAIN="${KEYCOUNT_KEYCHAIN:-$HOME/Library/Keychains/keycount-signing.keychain-db}"
KEYCHAIN_PW="${KEYCOUNT_KEYCHAIN_PW:-keycount-local-signing}"

ensure_searchable() {
    # Append the signing keychain to the user search list without dropping others.
    if ! security list-keychains -d user | sed 's/"//g' | grep -qF "$KEYCHAIN"; then
        local existing
        existing="$(security list-keychains -d user | sed 's/"//g' | xargs)"
        # shellcheck disable=SC2086
        security list-keychains -d user -s $existing "$KEYCHAIN"
    fi
}

if [[ -f "$KEYCHAIN" ]] \
    && security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY_CN"; then
    security unlock-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN" 2>/dev/null || true
    ensure_searchable
    echo "✅ 固定签名身份已就绪：$IDENTITY_CN"
    exit 0
fi

[[ -f "$CERT" && -f "$KEY" ]] || {
    echo "缺少 certs/cert.pem 或 certs/key.pem，无法导入。" >&2
    exit 1
}

# security import 按扩展名推断格式，必须带 .p12，否则报 "Unknown format"。
P12="$(mktemp -t keycount-identity).p12"
# 退出时锁回钥匙串，并把临时 p12 内容清零（私钥材料不留痕；文件留在 TMPDIR 无害）。
trap 'security lock-keychain "$KEYCHAIN" 2>/dev/null || true; cp /dev/null "$P12" 2>/dev/null || true' EXIT

echo "==> 用 certs/ 组装 PKCS#12（传输口令仅本地导入用）"
openssl pkcs12 -export -inkey "$KEY" -in "$CERT" \
    -name "$IDENTITY_CN" -passout pass:transport -out "$P12" >/dev/null 2>&1

echo "==> 创建专用签名钥匙串：$KEYCHAIN"
security create-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN" 2>/dev/null || true
security set-keychain-settings "$KEYCHAIN"               # 关闭自动锁定
security unlock-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P transport -f pkcs12 -A -T /usr/bin/codesign >/dev/null
# 授权 codesign 无弹窗使用该私钥
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PW" "$KEYCHAIN" >/dev/null 2>&1 || true
ensure_searchable

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY_CN"; then
    echo "✅ 已导入固定签名身份：$IDENTITY_CN"
    echo "   之后 ./build.sh 会自动用它签名；TCC 授权可跨版本保留。"
else
    echo "导入后仍未找到签名身份，请检查 certs/ 内容。" >&2
    exit 1
fi
