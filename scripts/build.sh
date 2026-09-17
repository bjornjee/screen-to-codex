#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:-dist/screen-to-codex.app}"
if [[ -d "$app" && "${CODE_SIGN_IDENTITY:--}" == "-" && "${REPLACE_ADHOC_APP:-0}" != "1" ]]; then
  printf '%s\n' 'Build stopped: replacing this ad-hoc signed app invalidates its Screen Recording grant.' >&2
  printf '%s\n' 'Use a stable CODE_SIGN_IDENTITY, or explicitly set REPLACE_ADHOC_APP=1 and re-authorize the resulting app.' >&2
  exit 1
fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/screen-to-codex-swift-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox --cache-path "${TMPDIR:-/tmp}/screen-to-codex-spm-cache" -c release
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
scripts/build-icon.sh "$app/Contents/Resources/AppIcon.icns"
cp .build/release/screen-to-codex "$app/Contents/MacOS/screen-to-codex"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --identifier local.screen-to-codex "$app"
if [[ "${CODE_SIGN_IDENTITY:--}" == "-" ]]; then
  printf '%s\n' 'Local ad-hoc build: changed binaries need a fresh Screen Recording grant. Use CODE_SIGN_IDENTITY with an Apple Development certificate to preserve grants across rebuilds.'
fi
printf 'Built %s\n' "$PWD/$app"
