#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d dist/screen-to-codex.app ]]; then
  scripts/build.sh
fi
# LaunchServices gives the app its own privacy identity; do not execute the Mach-O directly.
exec open "$PWD/dist/screen-to-codex.app"
