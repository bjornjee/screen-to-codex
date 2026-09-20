#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ $# -le 1 ]] || fail 'Usage: bash install.sh [absolute-install-directory]'
[[ "$(uname -s)" == Darwin ]] || fail 'screen-to-codex requires macOS.'
[[ "$(uname -m)" == arm64 ]] || fail 'This release requires an Apple Silicon Mac. Run from a native terminal, without Rosetta.'
macos="$(sw_vers -productVersion)"
[[ "${macos%%.*}" -ge 26 ]] || fail 'screen-to-codex requires macOS 26 or later.'

version='0.1.0'
asset='screen-to-codex-macos-arm64.zip'
base="https://github.com/bjornjee/screen-to-codex/releases/download/v$version"
install_dir="${1:-$HOME/Applications}"
[[ "$install_dir" == /* ]] || fail 'The install directory must be an absolute path.'
target="$install_dir/screen-to-codex.app"
[[ ! -e "$target" && ! -L "$target" ]] || fail "An app already exists at $target. Quit it and move it aside before installing; an update may need a fresh Screen Recording grant."

mkdir -p "$install_dir"
lock="$install_dir/.screen-to-codex-install.lock"
mkdir "$lock" 2>/dev/null || fail "Another installation may be in progress. If no installer is running, remove the empty lock directory: $lock"
scratch=''
cleanup() {
  if [[ -n "$scratch" ]]; then
    rm -rf "$scratch"
  fi
  rmdir "$lock"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
scratch="$(mktemp -d "$install_dir/.screen-to-codex.XXXXXX")"

printf 'Downloading screen-to-codex %s…\n' "$version"
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
  --connect-timeout 15 --max-time 120 --max-filesize 52428800 \
  --output "$scratch/$asset" "$base/$asset" || fail 'Download failed; no app was installed.'
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
  --connect-timeout 15 --max-time 30 --max-filesize 1024 \
  --output "$scratch/checksum" "$base/$asset.sha256" || fail 'Download failed; no app was installed.'
expected="$(cat "$scratch/checksum")"
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || fail 'Invalid release checksum.'
actual="$(shasum -a 256 "$scratch/$asset")"
[[ "${actual%% *}" == "$expected" ]] || fail 'Release checksum mismatch; no app was installed.'

ditto -x -k "$scratch/$asset" "$scratch/unpacked"
app="$scratch/unpacked/screen-to-codex.app"
[[ -d "$app" && ! -L "$app" ]] || fail 'Release does not contain the expected app bundle.'
codesign --verify --strict "$app" || fail 'App signature verification failed; no app was installed.'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == local.screen-to-codex ]] || fail 'Unexpected app identity.'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]] || fail 'Unexpected app version.'
[[ ! -e "$target" && ! -L "$target" ]] || fail "An app already exists at $target; no files were replaced."
mv "$app" "$target"
printf 'Installed %s\n' "$target"
printf '%s\n' 'Open the app in Finder, then press Control–Option–Space.'
printf '%s\n' 'If macOS blocks this unnotarized release, use System Settings → Privacy & Security → Open Anyway.'
printf '%s\n' 'Codex must be installed and signed in. Allow Screen Recording when prompted.'
