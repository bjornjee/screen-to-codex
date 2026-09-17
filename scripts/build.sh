#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:-$HOME/Applications/screen-to-codex.app}"
if [[ "$app" != *.app || -L "$app" || ( -e "$app" && ! -d "$app" ) ]]; then
  printf '%s\n' 'Build stopped: destination must be an app directory, not a symlink or file.' >&2
  exit 1
fi
requested_identity="${CODE_SIGN_IDENTITY:-$(git config --get screen-to-codex.signingIdentity || true)}"
# Resolve a name once, then remember its certificate hash in shared repository config.
identities="$(security find-identity -v -p codesigning)"
identity_pattern='^[[:space:]]*[0-9]+\) ([[:xdigit:]]{40}) "([^"]+)"$'
identity_count=0
identity=''
while IFS= read -r line; do
  if [[ "$line" =~ $identity_pattern ]]; then
    hash="${BASH_REMATCH[1]}"
    name="${BASH_REMATCH[2]}"
    if [[ -z "$requested_identity" || "$requested_identity" == "$hash" || "$requested_identity" == "$name" ]]; then
      identity="$hash"
      identity_count=$((identity_count + 1))
    fi
  fi
done <<< "$identities"
if [[ "$requested_identity" == - || ( "$identity_count" == 0 && -z "$requested_identity" ) ]]; then
  identity=-
  printf '%s\n' 'Local ad-hoc build: no certificate needed. Changed builds require renewed screen access.'
elif [[ "$identity_count" != 1 ]]; then
  printf '%s\n' 'Build stopped: the selected certificate is unavailable or the choice is ambiguous.' >&2
  printf '%s\n' 'If you have several, select one once with CODE_SIGN_IDENTITY="certificate name or SHA-1" scripts/build.sh.' >&2
  exit 1
fi
mkdir -p "$(dirname "$app")"
app="$(cd "$(dirname "$app")" && pwd)/$(basename "$app")"
if ! mkdir "$app.build-lock"; then
  printf 'Build stopped: another build owns %s.build-lock.\n' "$app" >&2
  exit 1
fi
stage_dir=''
cleanup() {
  if [[ -n "$stage_dir" ]]; then
    if [[ -d "$stage_dir/previous.app" && ! -e "$app" ]]; then
      mv "$stage_dir/previous.app" "$app"
    fi
    rm -rf "$stage_dir"
  fi
  rmdir "$app.build-lock"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
stage_dir="$(mktemp -d "$(dirname "$app")/.screen-to-codex-build.XXXXXX")"
old_requirement=''
if [[ -d "$app" ]]; then
  codesign --verify --strict "$app"
  old_requirement="$(codesign --display -r- "$app" 2>&1 | sed -n 's/^designated => //p')"
  [[ -n "$old_requirement" ]] || { printf 'Cannot read existing app identity.\n' >&2; exit 1; }
fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/screen-to-codex-swift-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox --cache-path "${TMPDIR:-/tmp}/screen-to-codex-spm-cache" -c release
staged_app="$stage_dir/screen-to-codex.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
scripts/build-icon.sh "$staged_app/Contents/Resources/AppIcon.icns"
cp .build/release/screen-to-codex "$staged_app/Contents/MacOS/screen-to-codex"
cp Info.plist "$staged_app/Contents/Info.plist"
codesign --force --sign "$identity" --identifier local.screen-to-codex "$staged_app"
codesign --verify --strict "$staged_app"
if [[ -n "$old_requirement" ]] && ! codesign --verify --strict -R="$old_requirement" "$staged_app"; then
  old_ad_hoc="$(codesign --display --verbose=2 "$app" 2>&1 | sed -n '/^Signature=adhoc$/p')"
  if [[ "$identity" == - && -n "$old_ad_hoc" && "${REPLACE_ADHOC_APP:-0}" == 1 ]]; then
    printf '%s\n' 'Replacing the ad-hoc app as requested. Re-authorize this build in Screen Recording settings.'
  else
    printf '%s\n' 'Build stopped: the update does not match the installed app identity. Existing app left intact.' >&2
    printf '%s\n' 'Choose a new app path for a signing migration. For an ad-hoc-to-ad-hoc update only, use REPLACE_ADHOC_APP=1 and re-authorize screen access.' >&2
    exit 1
  fi
fi
if [[ "$identity" != - ]]; then git config --local screen-to-codex.signingIdentity "$identity"; fi
if [[ -d "$app" ]]; then mv "$app" "$stage_dir/previous.app"; fi
mv "$staged_app" "$app"
printf 'Built %s\nSigning certificate: %s\n' "$app" "$identity"
