#!/usr/bin/env bash
# Sourced by build/test/preview scripts. Never changes xcode-select or system files.
set -euo pipefail

select_sdk() {
    if [[ -n "${KEYCOUNT_SDK:-}" ]]; then
        printf '%s\n' "$KEYCOUNT_SDK"
        return
    fi
    if [[ -n "${SDKROOT:-}" && -d "$SDKROOT" ]]; then
        printf '%s\n' "$SDKROOT"
        return
    fi
    # Prefer a locally installed SDK no newer than the running OS major version.
    # In particular CLT's macOS 27 SDK may reference SwiftUI macro plugins absent
    # from CLT. macOS 26 SDKs can build this macOS 13+ app without those plugins.
    local default_sdk
    default_sdk="$(xcrun --sdk macosx --show-sdk-path)"
    python3 - "$default_sdk" "$(sw_vers -productVersion)" <<'PY'
import pathlib, re, sys
default = pathlib.Path(sys.argv[1])
os_major = int(sys.argv[2].split('.')[0])
candidates = []
for sdk in default.parent.glob('MacOSX*.sdk'):
    match = re.fullmatch(r'MacOSX(\d+)\.(\d+)\.sdk', sdk.name)
    if match and int(match[1]) <= os_major and sdk.is_dir():
        candidates.append(((int(match[1]), int(match[2])), sdk))
print(max(candidates)[1] if candidates else default)
PY
}

KEYCOUNT_BUILD_SDK="$(select_sdk)"
KEYCOUNT_ARCH="${KEYCOUNT_ARCH:-$(uname -m)}"
KEYCOUNT_TARGET="${KEYCOUNT_ARCH}-apple-macosx13.0"
