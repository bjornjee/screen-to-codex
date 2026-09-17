#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

output="${1:?Usage: scripts/build-icon.sh output.icns}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/screen-to-codex-icon.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
iconset="$scratch/AppIcon.iconset"
mkdir -p "$iconset" "$(dirname "$output")"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Assets/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" Assets/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$output"
