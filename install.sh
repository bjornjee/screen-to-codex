#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ $# -le 1 ]] || fail 'Usage: bash install.sh [install-directory]'
[[ "$(uname -s)" == Darwin ]] || fail 'screen-to-codex requires macOS.'
[[ "$(uname -m)" == arm64 || "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]] \
  || fail 'This release requires an Apple Silicon Mac.'
macos="$(sw_vers -productVersion)"
[[ "${macos%%.*}" -ge 26 ]] || fail 'screen-to-codex requires macOS 26 or later.'

version='0.1.2'
asset='screen-to-codex-macos-arm64.zip'
base="https://github.com/bjornjee/screen-to-codex/releases/download/v$version"
install_dir="${1:-$HOME/Applications}"
mkdir -p "$install_dir"
install_dir="$(cd "$install_dir" && pwd -P)"
target="$install_dir/screen-to-codex.app"
check_destination() {
  [[ ! -L "$target" ]] || fail "The app destination is a symlink: $target"
  if [[ -e "$target" ]]; then
    [[ -d "$target" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null || true)" == local.screen-to-codex ]] \
      || fail "The destination contains a different app or file: $target"
  fi
}
check_destination

lock="$target.build-lock"
mkdir "$lock" 2>/dev/null || fail "Another installation may be in progress. If no installer is running, remove the empty lock directory: $lock"
scratch=''
backup=''
cleanup() {
  if [[ -n "$backup" && -d "$backup/screen-to-codex.app" && ! -e "$target" ]]; then
    mv "$backup/screen-to-codex.app" "$target"
  fi
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
check_destination
if [[ -d "$target" ]]; then
  backup="$(mktemp -d "$install_dir/screen-to-codex-backup.XXXXXX")"
  mv "$target" "$backup/screen-to-codex.app"
fi
mv "$app" "$target" || fail 'Could not install the new app; restoring the previous copy.'
printf 'Installed %s\n' "$target"
if [[ -n "$backup" ]]; then
  printf 'Previous copy saved at %s/screen-to-codex.app\n' "$backup"
  printf '%s\n' 'Quit any running copy and reopen the installed app. Screen Recording may need approval again.'
fi
printf '%s\n' 'Open the app in Finder, then press Control–Option–Space.'
printf '%s\n' 'If macOS blocks this unnotarized release, use System Settings → Privacy & Security → Open Anyway.'
printf '%s\n' 'Codex must be installed and signed in. Allow Screen Recording when prompted.'
