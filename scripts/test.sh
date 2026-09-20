#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/test-build.sh
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/screen-to-codex-swift-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
frameworks="$(xcode-select -p)/Library/Developer/Frameworks"
swift test --disable-sandbox --disable-xctest --enable-swift-testing \
  --cache-path "${TMPDIR:-/tmp}/screen-to-codex-spm-cache" \
  -Xswiftc "-F$frameworks" -Xlinker -rpath -Xlinker "$frameworks" \
  -Xlinker -rpath -Xlinker "$(dirname "$frameworks")/usr/lib" "$@"
bash Tests/InstallerTests/test-install.sh
