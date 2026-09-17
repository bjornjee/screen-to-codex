# screen-to-codex

A native macOS Tahoe menu-bar utility. Press **Control–Option–Space** to open
selection, then click and hold, drag a region, and release the mouse to open a
focused floating composer beside it. You do not need to keep the shortcut keys
held. A click without dragging keeps selection open. Send the screenshot and a
question to Codex, then read replies and ask follow-ups in the same rounded
Liquid Glass overlay. Closing it queues the disposable session for cleanup.

## Prerequisites

- macOS Tahoe 26 or later.
- An active Xcode or Command Line Tools installation with Swift 6 and the macOS 26
  SDK. The scripts use Apple's `swift`, `sips`, `iconutil`, and `codesign` tools.
- An installed, signed-in Codex runtime with ephemeral app-server support. Tested
  against the desktop-bundled CLI 0.154.0-alpha.6.2. The app checks these executable
  paths in order: `/Applications/Codex.app/Contents/Resources/codex`,
  `/opt/homebrew/bin/codex`, then `/usr/local/bin/codex`. A CLI elsewhere on `PATH`
  is not discovered automatically. The Codex desktop app need not be open.

There are no third-party Swift package dependencies. From the repository root,
check the selected development tools before building:

```sh
xcode-select -p
swift --version
xcrun --sdk macosx --show-sdk-version
```

## Build and run

For a first build, create the release app bundle and launch it through LaunchServices:

```sh
scripts/build.sh
scripts/run.sh
```

The output is `~/Applications/screen-to-codex.app`, shared by all worktrees.
Building installs the verified bundle there but does not launch or restart it.
For later launches, run **only `scripts/run.sh`**: it opens the existing bundle
without rebuilding, and builds only if that bundle is missing. A signing certificate
is optional for local source builds. When available, it is remembered and reused;
otherwise the app is signed ad hoc. Updates are checked against the installed app's
identity before replacement. Failed builds leave the existing app intact.

To check a new build while keeping the authorized bundle intact, use a separate
staging output (choose a new directory if this one already contains an app):

```sh
scripts/build.sh dist/staging/screen-to-codex.app
```

To run a staged app, quit the running copy first, then use
`scripts/run.sh dist/staging/screen-to-codex.app`. Both scripts accept an optional
bundle path. Keep only one copy running so it owns the global shortcut.

Always launch the `.app` with Finder or `scripts/run.sh`. Running the executable
inside `Contents/MacOS` directly can attribute macOS privacy requests to the
terminal's host instead of screen-to-codex.

## Capture and chat

1. Launch the app and look for the viewfinder icon in the menu bar. No chat window
   appears at launch; keep the menu-bar process running to receive the shortcut.
2. Press **Control–Option–Space**, then release the shortcut keys.
3. Click and hold, drag a region on one display, then release the mouse. A click
   without dragging keeps selection open; **Escape** cancels selection.
4. If screen access is missing, use **Open Settings** in the setup window before
   selecting a region. After granting access, choose **Capture Region**.
   A successful capture opens the floating screenshot composer beside the region.
5. Enter a question, optionally choose **Model** and **Effort**, and click **Send**.
   Read the reply and send follow-ups in the same overlay; the conversation retains
   the screenshot context without another capture.
6. Close the overlay when finished. Cleanup is silent, with no confirmation toast.
   To capture a different region, close the current chat first; the shortcut brings
   an existing chat forward instead of starting a second one.

The menu also offers **Capture region**, **Screen access…**, **Change shortcut…**, **Retry pending
cleanup**, and **Quit screen-to-codex**.

### Model and effort defaults

Each new overlay reads your resolved Codex `model` and `model_reasoning_effort`
settings without changing them. Unset settings use runtime catalog defaults;
unavailable saved choices fall back to an available option with a visible notice.
Only visible image-capable models with supported effort choices are offered.

Model and Effort changes apply to the next message, including follow-ups. The
menus are disabled while sending. Changing model resets an unsupported effort to
that model's default. Manual choices last only until the overlay closes. If model
settings fail to load, use the inline retry after checking the runtime installation
and sign-in.

## Screen Recording permission troubleshooting

Screen access is checked before selection begins, and again before taking the
screenshot. On first launch, allow **screen-to-codex** under System Settings → Privacy &
Security → Screen & System Audio Recording. macOS uses this combined permission
name for screenshots too. System audio and microphone capture are explicitly
disabled. No Accessibility permission is required for the global shortcut.
Use **Open Settings** in the app's **Screen access…** window to start setup. A
temporary helper watches for macOS quitting the app and reopens the same bundle
once, showing **Ready to capture** when access is available. The helper expires
after three minutes; **Not Now**, closing setup, or the app's **Quit** command
cancels it. **Check Again** rechecks access without rebuilding or changing any
system settings. Returning from Settings also refreshes the status.

The menu-bar process must be running to receive its global shortcut. If you change
permission outside this setup flow, or after the helper expires, reopen the app
with `scripts/run.sh` if macOS quits it.

If capture still fails:

1. Reopen the unchanged `.app` with `scripts/run.sh` or Finder, especially if macOS
   quit it while you changed permission. Do not rebuild as a troubleshooting step.
2. In **Screen access…**, expand **Already enabled, but still blocked?** and use
   **Show this app in Finder** to identify the exact bundle you are launching.
   An enabled switch for an older build does not prove the current binary has access.
3. If you intentionally replaced an ad-hoc build, follow the signing guidance below
   to remove the stale entry and authorize the replacement once.
4. If the shortcut does nothing, confirm the menu-bar icon is present, try **Capture
   region** from its menu, or choose another shortcut with **Change shortcut…**.

Do not edit macOS privacy databases or weaken signature checks to work around a
stale grant.

### Local development signing

**No developer account or certificate is required to build locally.** Without a
configured or available signing certificate, `scripts/build.sh` creates an ad-hoc
signed app. macOS can require screen access again when its binary changes. A
changed ad-hoc app is protected from accidental replacement; to intentionally
update it, use `REPLACE_ADHOC_APP=1 scripts/build.sh`, then re-authorize that copy.
This override cannot downgrade a certificate-signed app or change its signer.

For developers who want permission continuity across rebuilds, optionally create
an **Apple Development** certificate once in **Xcode → Settings → Apple
Accounts → Manage Certificates → +**. Add your Apple account first if necessary.
Check availability with `security find-identity -v -p codesigning`.

When exactly one valid identity exists, the first build selects it and remembers
its certificate hash in the repository's local Git configuration, shared across
worktrees. If several exist, select one for the first build:

```sh
CODE_SIGN_IDENTITY='Apple Development: Your Name (TEAMID)' scripts/build.sh
```

Subsequent builds need only `scripts/build.sh`. The build refuses to fall back to
ad-hoc signing if the remembered certificate is missing or expired. A replacement
certificate can be selected with the same environment variable; an update must
still satisfy the installed app's signing requirement. The build never loosens
that requirement or edits macOS permissions.

**One-time migration from older ad-hoc builds:** quit the old copy in `dist`, build
and launch the new default in `~/Applications`, then remove the stale Screen
Recording entry and grant access to this copy once. Ad-hoc identity depends on the
old binary's hash, so a changed build cannot preserve that identity. If the new
default already contains an ad-hoc app, move it aside in Finder before this
one-time migration.

If switching Screen Recording off/on still leaves the old entry ineffective,
quit the app and reset only its stale approval before reopening the signed copy:

```sh
tccutil reset ScreenCapture local.screen-to-codex
scripts/run.sh
```

Use **Open Settings** in the app and approve the fresh request. This reset removes
the old grant; it does not grant access automatically.
This is a one-time migration repair, not part of routine builds.

The build does not create certificates, change trust settings, or reset system
permissions. [Apple explains how signing requirements identify updates](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

### Distribution to other users

Users of a packaged release do not need Xcode, an Apple developer account, or their
own certificate. The publisher should sign releases with **Developer ID Application**
and notarize them before distribution; signing and notarization are publisher
responsibilities. Keep the bundle identifier and signing identity consistent for
updates. Apple Development signing is for local development, not the public release
process. This repository's build script creates local builds; it does not yet
publish notarized release packages. See [Apple's distribution guidance](https://developer.apple.com/developer-id/).

## Conversation and cleanup

Each overlay owns one `codex app-server --stdio` child and one `ephemeral: true`
task. The desktop app does not need to open. Existing tasks are never resumed,
modified, or deleted. Codex uses its existing sign-in and model configuration.
The task starts in read-only mode; supported approval and question requests
appear in the overlay, and unsupported actions are rejected.

The composer has Model and Effort menus populated by the installed runtime.
Defaults are read through `config/read`, respecting `~/.codex` (or the runtime's
configured `CODEX_HOME`) without modifying it. Config reads have a
15-second deadline. Catalog loading is asynchronous, capped at five pages of 50
entries, and offers an inline retry if settings cannot be loaded.

The header displays the app icon and “Screen to Codex.” A single rounded composer
groups the question, model/effort menus, and circular Send button. Completed replies use
Foundation's Markdown parser for emphasis, headings, lists, links, and code.
Each reply is parsed once off the main thread, capped at 64,000 characters and
256 formatted blocks (with a visible truncation notice beyond that limit);
streaming text remains visible while it arrives. Only HTTP/HTTPS links are active.
The screenshot row becomes compact after sending, leaving more room to read.

Captures are stored in a private, app-owned temporary directory. Image bytes
are sent as a structured data URL, never as a pathname; the source PNG is removed
once the turn is accepted. Follow-ups use the same live task. Closing clears the
in-memory transcript, queues cleanup, stops the owned runtime, and removes the
session directory without displaying a toast. Startup and periodic cleanup skip
locked live sessions and unrelated files. Failed deletions retain their ownership
markers for retry and do not block other sessions in the cleanup batch.
If cleanup is pending, the menu-bar tooltip says so; use **Retry pending cleanup**
or let startup/periodic cleanup retry automatically.
No clipboard, screenshot gallery, or local transcript database.

Opening is reserved before screenshot storage begins, preventing overlapping
captures from creating competing chats. Quit waits for pending opening and cleanup
work. The ownership marker and lock are the single source of cleanup eligibility;
there is no separate pending-marker file.

The real integration test verifies image recognition, a follow-up after source
PNG deletion, local directory cleanup, and failure to resume the ephemeral task
from a fresh runtime. This is local lifecycle behavior, not a claim of upstream
provider data erasure. See [the runtime decision](docs/adr/001-ephemeral-runtime.md).

## Verification

The generated app icon and 32-pixel favicon live in `Assets/`. The build exports
the native macOS icon at standard and Retina sizes using `sips` and `iconutil`.
The generation prompt is recorded in [Assets/README.md](Assets/README.md).

Format or check Swift source with the toolchain's built-in formatter:

```sh
swift format format --in-place --recursive Sources Tests Package.swift
swift format lint --strict --recursive Sources Tests Package.swift
```

Run the local suite without sending a real Codex request:

```sh
scripts/test.sh
```

The suite includes build identity/replacement checks, native process-exit recovery,
pipe streaming, payload limits, and cleanup ownership tests.
The real-runtime integration test is opt-in and requires the desktop-bundled CLI
at `/Applications/Codex.app/Contents/Resources/codex` (it does not use the app's CLI
fallback paths):

```sh
SCREEN_TO_CODEX_INTEGRATION=1 scripts/test.sh
```

This sends a generated blue-circle image and a follow-up using the signed-in Codex
account, consuming account usage. It creates only its own disposable test task;
it does not capture the screen or exercise macOS permission dialogs.

The user verified hotkey → click-and-drag → mouse-up → screenshot and chat on
2026-09-16; runtime logs confirm capture completion and chat opening. Further live
acceptance covers keyboard cancellation, same-overlay reply/follow-up, and closing during a turn.
The permission failure seen during development was traced to direct-launch
attribution and stale ad-hoc signatures. Adding the exact current bundle in
System Settings and restarting that unchanged build resolved capture access.

Current bounds: one selected display per capture, 4096-pixel maximum image edge,
12 MB PNG, 8000-character questions, 40 visible messages, and bounded protocol
frames and pending requests. The overlay honors Reduce Transparency and Reduce
Motion. The [accepted design reference](docs/design/overlay-tahoe.png) is a mockup,
not runtime verification evidence.
