#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/screen-to-codex-build-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/repo/scripts"
cp "$repo/scripts/build.sh" "$fixture/repo/scripts/build.sh"
cp "$repo/Info.plist" "$fixture/repo/Info.plist"
git -C "$fixture/repo" init -q
cat > "$fixture/bin/security" <<'SH'
#!/bin/bash
printf '%s\n' "${TEST_IDENTITIES:-0 valid identities found}"
SH
cat > "$fixture/bin/swift" <<'SH'
#!/bin/bash
mkdir -p .build/release
printf '%s' "${TEST_VERSION:-first}" > .build/release/screen-to-codex
SH
cat > "$fixture/repo/scripts/build-icon.sh" <<'SH'
#!/bin/bash
printf icon > "$1"
SH
cat > "$fixture/bin/codesign" <<'SH'
#!/bin/bash
set -euo pipefail
target="${!#}"
case "$1" in
  --force)
    [[ "${TEST_SIGN_FAILURE:-0}" == 0 ]] || exit 1
    printf '%s' "$3" > "$target/signer"
    ;;
  --display)
    if [[ "$2" == --verbose=2 ]]; then
      [[ "$(cat "$target/signer")" != - ]] || printf 'Signature=adhoc\n' >&2
    elif [[ "$(cat "$target/signer")" == - ]]; then
      printf 'designated => cdhash H"%s"\n' "$(cat "$target/Contents/MacOS/screen-to-codex")" >&2
    else
      printf 'designated => identifier "local.screen-to-codex" and certificate leaf = H"%s"\n' "$(cat "$target/signer")" >&2
    fi
    ;;
  --verify)
    [[ -f "$target/signer" ]] || exit 1
    for argument in "$@"; do
      if [[ "$argument" == -R=* ]]; then
        if [[ "$(cat "$target/signer")" == - ]]; then
          [[ "$argument" == "-R=cdhash H\"$(cat "$target/Contents/MacOS/screen-to-codex")\"" ]] || exit 1
        else
          [[ "$argument" == "-R=identifier \"local.screen-to-codex\" and certificate leaf = H\"$(cat "$target/signer")\"" ]] || exit 1
        fi
      fi
    done
    ;;
  *) exit 2 ;;
esac
SH
chmod +x "$fixture/bin/"* "$fixture/repo/scripts/"*.sh
export PATH="$fixture/bin:$PATH"
unset CODE_SIGN_IDENTITY REPLACE_ADHOC_APP
app="$fixture/output with spaces/screen-to-codex.app"
build() { bash "$fixture/repo/scripts/build.sh" "$app" > "$fixture/output.log" 2>&1; }
fail() { cat "$fixture/output.log"; printf 'FAIL: %s\n' "$1" >&2; exit 1; }
build || fail 'first build must work without a certificate'
[[ "$(cat "$app/signer")" == - ]] || fail 'certificate-free build must be ad-hoc signed'
if git -C "$fixture/repo" config --get screen-to-codex.signingIdentity; then fail 'ad-hoc mode must not be pinned'; fi
printf 'PASS: certificate-free first build is available\n'
export TEST_VERSION=changed
if build; then fail 'changed ad-hoc update needs explicit reauthorization acknowledgment'; fi
[[ "$(cat "$app/Contents/MacOS/screen-to-codex")" == first ]] || fail 'ad-hoc failure changed app'
printf 'PASS: changed ad-hoc identity is protected by default\n'
export REPLACE_ADHOC_APP=1
build || fail 'explicit ad-hoc replacement must work without a certificate'
[[ "$(cat "$app/Contents/MacOS/screen-to-codex")" == changed ]] || fail 'explicit replacement did not update app'
unset REPLACE_ADHOC_APP TEST_VERSION
printf 'PASS: acknowledged ad-hoc update is available\n'
app="$fixture/signed output/screen-to-codex.app"

first_identity=1111111111111111111111111111111111111111
second_identity=2222222222222222222222222222222222222222
export TEST_IDENTITIES="  1) $first_identity \"Apple Development: Test\""
build || fail 'first certificate-signed build'
[[ "$(cat "$app/signer")" == "$first_identity" ]] || fail 'must use the certificate instead of ad-hoc signing'
[[ "$(git -C "$fixture/repo" config --get screen-to-codex.signingIdentity)" == "$first_identity" ]] || fail 'must remember identity across worktrees'
printf 'PASS: one certificate is selected and remembered\n'

export TEST_IDENTITIES="  1) $first_identity \"Apple Development: Test\"
  2) $second_identity \"Apple Development: Other\""
export TEST_VERSION=second
build || fail 'same identity update'
[[ "$(cat "$app/Contents/MacOS/screen-to-codex")" == second ]] || fail 'verified update must replace executable'
printf 'PASS: pinned identity survives another certificate being added\n'

export CODE_SIGN_IDENTITY=- REPLACE_ADHOC_APP=1
if build; then fail 'signed app must not be downgraded to ad-hoc'; fi
unset CODE_SIGN_IDENTITY REPLACE_ADHOC_APP
printf 'PASS: signed app cannot be downgraded to ad-hoc\n'

export TEST_SIGN_FAILURE=1 TEST_VERSION=broken
if build; then fail 'signing failure must stop update'; fi
[[ "$(cat "$app/Contents/MacOS/screen-to-codex")" == second ]] || fail 'signing failure changed installed executable'
unset TEST_SIGN_FAILURE
printf 'PASS: signing failure leaves existing app intact\n'

export CODE_SIGN_IDENTITY="$second_identity"
if build; then fail 'different identity must stop update'; fi
[[ "$(cat "$app/signer")" == "$first_identity" ]] || fail 'identity mismatch changed installed app'
[[ "$(cat "$app/Contents/MacOS/screen-to-codex")" == second ]] || fail 'identity mismatch changed installed executable'
unset CODE_SIGN_IDENTITY
printf 'PASS: identity change leaves existing app intact\n'

export TEST_IDENTITIES="  1) $second_identity \"Apple Development: Other\""
if build; then fail 'missing pinned certificate must not select a different certificate'; fi
printf 'PASS: missing pinned identity does not silently rotate\n'

git -C "$fixture/repo" config --unset screen-to-codex.signingIdentity
export TEST_IDENTITIES="  1) $first_identity \"Apple Development: Test\"
  2) $second_identity \"Apple Development: Other\""
if build; then fail 'multiple unconfigured certificates must not select arbitrarily'; fi
printf 'PASS: ambiguous identities fail clearly\n'

export TEST_IDENTITIES="  1) $first_identity \"Apple Development: Test\""
mkdir "$app.build-lock"
if build; then fail 'concurrent build must not replace the shared app'; fi
rmdir "$app.build-lock"
printf 'PASS: concurrent installation rejected\n'

ln -s "$app" "$fixture/app-link.app"
app="$fixture/app-link.app"
if build; then fail 'symlink output must not be replaced'; fi
printf 'PASS: symlink destination rejected\n'
