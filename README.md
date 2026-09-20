# screen-to-codex

A native macOS Tahoe menu-bar utility. Press **Control–Option–Space** to open
selection, then click and hold, drag a region, and release the mouse to open a
focused floating composer beside it. You do not need to keep the shortcut keys
held. A click without dragging keeps selection open. Send the screenshot and a
question to Codex, then read replies and ask follow-ups in the same rounded
Liquid Glass overlay. Closing it queues the disposable session for cleanup.

## Install

- An Apple Silicon Mac running macOS Tahoe 26 or later.
- An installed, signed-in Codex runtime with ephemeral app-server support. Tested
  against the desktop-bundled CLI 0.154.0-alpha.6.2. The app checks these executable
  paths in order: `/Applications/Codex.app/Contents/Resources/codex`,
  `/opt/homebrew/bin/codex`, then `/usr/local/bin/codex`. A CLI elsewhere on `PATH`
  is not discovered automatically. The Codex desktop app need not be open.

Download and run the installer; no Xcode, Git checkout, or compilation is needed:

```sh
curl -fLsS --proto '=https' --proto-redir '=https' \
  https://github.com/bjornjee/screen-to-codex/releases/latest/download/install.sh \
  -o install.sh && bash install.sh
```

The installer downloads the prebuilt app from its pinned GitHub release, checks
its SHA-256 checksum and code signature, and installs it to `~/Applications`.
It does not use `sudo`, launch the app, or replace an existing installation.
To choose a different directory, run `bash install.sh "/absolute/path/Applications"`.
If you already cloned the repository, you can run `bash install.sh` directly.

Open `~/Applications/screen-to-codex.app` in Finder, then press
**Control–Option–Space**. Allow **Screen Recording** when prompted.
The first release is **ad-hoc signed and not notarized**. If macOS blocks it,
follow [Apple's instructions](https://support.apple.com/en-gb/102445): attempt to
open it, then use **System Settings → Privacy & Security → Open Anyway**.
The installer does not remove quarantine attributes or disable Gatekeeper.

For an update, quit the app and move the old bundle aside before rerunning the
installer. Keep the old bundle if you may want to roll back. A new ad-hoc build
may need a fresh Screen Recording grant. To uninstall, quit and move the installed
app to the Trash.

You can also download the ZIP from [Releases](https://github.com/bjornjee/screen-to-codex/releases/latest)
and move the extracted app into your Applications folder.

## Build from source

Development requires an active Xcode or Command Line Tools installation with Swift 6
and the macOS 26 SDK. The scripts use Apple's `swift`, `sips`, `iconutil`, and `codesign` tools.
There are no third-party Swift package dependencies. From the repository root,
check the selected development tools before building:

```sh
xcode-select -p
swift --version
xcrun --sdk macosx --show-sdk-version
```

### Build and run

For a first build, create the release app bundle and launch it through LaunchServices:

```sh
scripts/build.sh
scripts/run.sh
```

The output is `dist/screen-to-codex.app`. Building does not launch or install it.
For later launches, run **only `scripts/run.sh`**: it opens the existing bundle
without rebuilding, and builds only if that default bundle is missing. The build
script refuses to overwrite an existing ad-hoc signed bundle, protecting its
Screen Recording grant. Do not use the replacement override for routine launches.

To check a new build while keeping the authorized bundle intact, use a separate
staging output (choose a new directory if this one already contains an app):

```sh
scripts/build.sh dist/staging/screen-to-codex.app
```

`scripts/run.sh` always opens the default output; it does not accept a staging
path. If you intentionally want to use the staged app, quit the running copy and
open that exact bundle with Finder. A new ad-hoc build may need its own permission
grant.

Always launch the `.app` with Finder or `scripts/run.sh`. Running the executable
inside `Contents/MacOS` directly can attribute macOS privacy requests to the
terminal's host instead of screen-to-codex.

## Capture and chat

1. Launch the app and look for the viewfinder icon in the menu bar. No chat window
   appears at launch; keep the menu-bar process running to receive the shortcut.
2. Press **Control–Option–Space**, then release the shortcut keys.
3. Click and hold, drag a region on one display, then release the mouse. A click
   without dragging keeps selection open; **Escape** cancels selection.
4. Allow screen access if prompted, then repeat the capture after granting it.
   A successful capture opens the floating screenshot composer beside the region.
5. Enter a question, optionally choose **Model** and **Effort**, and click **Send**.
   Read the reply and send follow-ups in the same overlay; the conversation retains
   the screenshot context without another capture.
6. Close the overlay when finished. Cleanup is silent, with no confirmation toast.
   To capture a different region, close the current chat first; the shortcut brings
   an existing chat forward instead of starting a second one.

The menu also offers **Capture region**, **Change shortcut…**, **Retry pending
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

Selection opens immediately; permission is checked after mouse release, before
any screenshot is taken. On first capture, allow **screen-to-codex** under System Settings → Privacy &
Security → Screen & System Audio Recording. macOS uses this combined permission
name for screenshots too. System audio and microphone capture are explicitly
disabled. No Accessibility permission is required for the global shortcut.
If macOS quits the app during the permission change, reopen the `.app` once.
The menu-bar process must be running to receive its global shortcut.

If capture still fails:

1. Reopen the unchanged `.app` with `scripts/run.sh` or Finder, especially if macOS
   quit it while you changed permission. Do not rebuild as a troubleshooting step.
2. Confirm that the permission entry belongs to the exact bundle you are launching.
   An enabled switch for an older build does not prove the current binary has access.
3. If you intentionally replaced an ad-hoc build, follow the signing guidance below
   to remove the stale entry and authorize the replacement once.
4. If the shortcut does nothing, confirm the menu-bar icon is present, try **Capture
   region** from its menu, or choose another shortcut with **Change shortcut…**.

Do not edit macOS privacy databases or weaken signature checks to work around a
stale grant.

### Local development signing

The default build uses ad-hoc signing. A changed binary has a new code identity,
so an old enabled Screen Recording entry can fail with “Failed to match existing
code requirement.” Quit the app, remove its stale permission entry, reopen it,
and grant screen access to the new build. Do not repeatedly rebuild while testing
an already granted binary. `scripts/build.sh` refuses to overwrite an existing
bundle with ad-hoc signing by default. For an intentional update only, use
`REPLACE_ADHOC_APP=1 scripts/build.sh`, then re-authorize that exact build once.
Use `scripts/run.sh` to reopen the current app without rebuilding.
To prepare an update without replacing the authorized app, use the separate
staging output described above.

For permission continuity across rebuilds, use an existing Apple Development
signing identity:

```sh
CODE_SIGN_IDENTITY='Apple Development: Your Name (TEAMID)' scripts/build.sh
```

The build does not create certificates, change trust settings, or reset system
permissions. [Apple DTS confirms this ad-hoc signing behavior](https://developer.apple.com/forums/thread/819406).

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

The suite includes pipe streaming, payload limits, cleanup ownership, and installer
tests. Installer tests use local signed fixtures and stub only the network and platform
checks; they exercise real archive extraction, checksums, signatures, and filesystem writes.
Run just the installer tests with `bash Tests/InstallerTests/test-install.sh`.
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

## Publishing a release

Build on Apple Silicon from the tested release commit. Update the version in
`Info.plist` and `install.sh` together; never replace assets for an existing version.
Use a new staging directory so an existing authorized local build is untouched:

```sh
CODE_SIGN_IDENTITY=- scripts/build.sh dist/releases/v0.1.0/screen-to-codex.app
codesign --verify --strict dist/releases/v0.1.0/screen-to-codex.app
ditto -c -k --keepParent dist/releases/v0.1.0/screen-to-codex.app \
  dist/releases/v0.1.0/screen-to-codex-macos-arm64.zip
shasum -a 256 dist/releases/v0.1.0/screen-to-codex-macos-arm64.zip \
  | cut -d ' ' -f 1 > dist/releases/v0.1.0/screen-to-codex-macos-arm64.zip.sha256
```

Publish the ZIP, its `.sha256` file, and the matching `install.sh` together in a
GitHub release tagged at that exact commit. Test a fresh installation from the
public release URLs. Developer ID signing and notarization require the appropriate
Apple distribution credentials; Apple Development signing is not a substitute.
See [the release decision and rollback procedure](docs/adr/002-release-installation.md).
