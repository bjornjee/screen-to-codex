# screen-to-codex

A native macOS Tahoe menu-bar utility. Press **Control–Option–Space** to open
selection, then click and hold, drag a region, and release the mouse to open a
focused floating composer beside it. You do not need to keep the shortcut keys
held. A click without dragging keeps selection open. Send the screenshot and a
question to Codex, then read replies and ask follow-ups in the same rounded
Liquid Glass overlay. Closing it queues the disposable session for cleanup.

## Build and run

Requires macOS 26+, Swift 6, and an installed, signed-in Codex CLI with ephemeral
app-server support. Tested against the desktop-bundled CLI 0.154.0-alpha.6.2.
There are no third-party package dependencies.

```sh
scripts/build.sh
scripts/run.sh
```

Launching opens only a menu-bar viewfinder icon. The global shortcut starts
selection; no chat appears until you release the mouse. The menu also contains
Capture region, Change shortcut, Retry pending cleanup, and Quit.

Always launch the `.app` with Finder or `scripts/run.sh`. Running the executable
inside `Contents/MacOS` directly can attribute macOS privacy requests to the
terminal's host instead of screen-to-codex.

Selection opens immediately; permission is checked after mouse release, before
any screenshot is taken. On first capture, allow **screen-to-codex** under System Settings → Privacy &
Security → Screen & System Audio Recording. macOS uses this combined permission
name for screenshots too. System audio and microphone capture are explicitly
disabled. No Accessibility permission is required for the global shortcut.
If macOS quits the app during the permission change, reopen the `.app` once.
The menu-bar process must be running to receive its global shortcut.

### Local development signing

The default build uses ad-hoc signing. A changed binary has a new code identity,
so an old enabled Screen Recording entry can fail with “Failed to match existing
code requirement.” Quit the app, remove its stale permission entry, reopen it,
and grant screen access to the new build. Do not repeatedly rebuild while testing
an already granted binary. `scripts/build.sh` refuses to overwrite an existing
bundle with ad-hoc signing by default. For an intentional update only, use
`REPLACE_ADHOC_APP=1 scripts/build.sh`, then re-authorize that exact build once.
Use `scripts/run.sh` to reopen the current app without rebuilding.
To prepare an update without replacing the authorized app, pass a separate output
path, for example `scripts/build.sh dist/model-controls/screen-to-codex.app`.

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
Only visible image-capable models are offered. Effort choices track the selected
model; unsupported choices reset to that model's default. Both selections apply
to the next message, including follow-ups in the same ephemeral task, and are
disabled while sending. Each new overlay reads the user's resolved Codex model
and `model_reasoning_effort` through `config/read`, respecting `~/.codex` (or the
runtime's configured `CODEX_HOME`) without modifying it. Manual choices last only
for the open overlay. Unset settings use the catalog defaults; unsupported saved
choices use an available option with a visible notice. Config reads have a
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

```sh
scripts/test.sh
SCREEN_TO_CODEX_INTEGRATION=1 scripts/test.sh
```

The second command sends a generated blue-circle image using the signed-in Codex
account. It creates only its own disposable test task. The suite includes pipe
streaming, payload limits, and cleanup ownership tests.

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
