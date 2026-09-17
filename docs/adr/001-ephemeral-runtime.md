# Ephemeral Codex runtime

Context: closing an overlay must discard its private screenshot conversation.
Decision: one stdio Codex app-server process and one `ephemeral: true` thread per overlay.
Authority: the installed Codex executable uses the existing sign-in; no credentials are copied.
Ownership: Swift owns UI, capture and temporary files; Codex owns inference and in-memory context.
Images cross the protocol as bounded data URLs, never as deferred source-file references.
Close ends the owned process before local cleanup; startup sweeps only unlocked owned directories.
No existing task is resumed, modified or deleted; ephemeral threads are never persisted as history.
Failure: keep draft on send failure, fail closed on unknown approval types, retain cleanup markers on error.
Rollback: quit/remove this app; no migrations, saved task edits, or settings changes in Codex.
Limits: provider retention is outside this guarantee; upstream erasure is not promised.

## Boundary and scale review

Screenshots and prompts are private data. After Send, the app passes them to the
explicitly launched local Codex runtime. Provider and tool access follow that
runtime's configuration and approval policy; this is not a connector-free sandbox.
No shell interpolation, HTTP listener, credential storage, or screenshot logs.
The read-only filesystem sandbox and user-reviewed approvals constrain requested actions.
Malformed/oversized JSON frames and captures are rejected. Unknown server
requests fail visibly rather than approving an action. Temporary directories
are owner-only, UUID named, version marked and protected by an OS file lock;
symlinks are excluded from cleanup. Live sessions keep their lock.

One open overlay, one in-flight turn, bounded image bytes, bounded retained
transcript and bounded event queue. Encoding, protocol I/O and cleanup run off
the main actor. Orphans are enumerated in background batches, never per keystroke.
This app invokes the installed runtime, not repository-supplied executables.
The production protocol integration test verifies a real image answer and
same-thread follow-up after deleting the PNG, followed by local cleanup and
rejection of `thread/resume` from a fresh runtime. `thread/read` alone is not
evidence of disposal because a persisted task can also be absent from memory.
