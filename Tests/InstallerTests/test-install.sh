#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
repo="$PWD"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/screen-to-codex-installer-tests.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/payload/screen-to-codex.app/Contents/MacOS"
app="$scratch/payload/screen-to-codex.app"
cp /usr/bin/true "$app/Contents/MacOS/screen-to-codex"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app" >/dev/null 2>&1
ditto -c -k --keepParent "$app" "$scratch/app.zip"
shasum -a 256 "$scratch/app.zip" | cut -d ' ' -f 1 > "$scratch/app.zip.sha256"
cat > "$scratch/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
[[ "${TEST_NETWORK_FAILURE:-0}" == 0 ]] || exit 22
output=''
url=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  *.zip.sha256) cp "$TEST_FIXTURE/app.zip.sha256" "$output" ;;
  *.zip) cp "$TEST_FIXTURE/app.zip" "$output" ;;
  *) exit 2 ;;
esac
CURL
cat > "$scratch/bin/uname" <<'UNAME'
#!/usr/bin/env bash
case "$1" in
  -s) printf '%s\n' "${TEST_OS:-Darwin}" ;;
  -m) printf '%s\n' "${TEST_ARCH:-arm64}" ;;
esac
UNAME
cat > "$scratch/bin/sw_vers" <<'VERSION'
#!/usr/bin/env bash
printf '%s\n' "${TEST_MACOS:-26.0}"
VERSION
chmod +x "$scratch/bin/"*
export PATH="$scratch/bin:$PATH" TEST_FIXTURE="$scratch"

expect_failure() {
  local expected="$1"
  shift
  if "$@" > "$scratch/output" 2>&1; then
    printf 'FAIL: expected failure containing %s\n' "$expected" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$scratch/output"; then
    cat "$scratch/output" >&2
    exit 1
  fi
}

case "${1:-all}" in
  all|success)
    bash "$repo/install.sh" "$scratch/Applications with spaces"
    codesign --verify --strict "$scratch/Applications with spaces/screen-to-codex.app"
    printf '%s\n' 'PASS: valid release installs into a path containing spaces'
    [[ "${1:-all}" == all ]] || exit 0
    ;;
  *) exit 2 ;;
esac

expect_failure 'already exists' bash "$repo/install.sh" "$scratch/Applications with spaces"
printf '%s\n' 'PASS: existing installation is preserved'
expect_failure 'macOS' env TEST_OS=Linux bash "$repo/install.sh" "$scratch/linux"
printf '%s\n' 'PASS: unsupported operating system rejected'
expect_failure 'Apple Silicon' env TEST_ARCH=x86_64 bash "$repo/install.sh" "$scratch/intel"
printf '%s\n' 'PASS: unsupported architecture rejected'
expect_failure 'macOS 26' env TEST_MACOS=25.0 bash "$repo/install.sh" "$scratch/old"
printf '%s\n' 'PASS: unsupported macOS version rejected'
expect_failure 'Download failed' env TEST_NETWORK_FAILURE=1 bash "$repo/install.sh" "$scratch/offline"
[[ ! -e "$scratch/offline/screen-to-codex.app" ]]
printf '%s\n' 'PASS: failed download leaves no installation'
printf '%064d\n' 0 > "$scratch/app.zip.sha256"
expect_failure 'checksum' bash "$repo/install.sh" "$scratch/corrupt"
[[ ! -e "$scratch/corrupt/screen-to-codex.app" ]]
printf '%s\n' 'PASS: checksum mismatch leaves no installation'
printf '%s\n' 'not-a-checksum' > "$scratch/app.zip.sha256"
expect_failure 'checksum' bash "$repo/install.sh" "$scratch/bad-checksum"
printf '%s\n' 'PASS: malformed checksum rejected'
printf 'tampered\n' >> "$app/Contents/MacOS/screen-to-codex"
ditto -c -k --keepParent "$app" "$scratch/app.zip"
shasum -a 256 "$scratch/app.zip" | cut -d ' ' -f 1 > "$scratch/app.zip.sha256"
expect_failure 'signature' bash "$repo/install.sh" "$scratch/unsigned"
[[ ! -e "$scratch/unsigned/screen-to-codex.app" ]]
printf '%s\n' 'PASS: invalid signature leaves no installation'
