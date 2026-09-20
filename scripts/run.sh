#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:-$HOME/Applications/screen-to-codex.app}"
if [[ ! -d "$app" ]]; then
  scripts/build.sh "$app"
fi
# LaunchServices gives the app its own privacy identity; do not execute the Mach-O directly.
exec open "$app"
