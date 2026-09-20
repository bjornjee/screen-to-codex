# Local app updates

- An enabled Screen Recording switch is not proof that the current binary is authorized.
  TCC logs can show a stored ad-hoc `cdhash` that differs from the running bundle.
- Re-signing after changing resources, including the icon, can change that identity too.
- Do not rebuild or re-sign an authorized app during permission diagnosis. Launch the
  existing bundle with `scripts/run.sh` and verify `hotkey.registered` in the logs.
- When configured, builds reuse a certificate remembered in local Git config; a
  missing pinned certificate must never silently fall back to ad-hoc signing.
- Certificates are optional for local source builds. First-time ad-hoc builds work
  without one; changed ad-hoc updates require explicit replacement and a fresh grant.
  Packaged release signing and notarization belong to the publisher, not end users.
- The default bundle lives in `~/Applications`, shared across worktrees. Migrating
  from an old ad-hoc bundle requires a one-time grant to the certificate-signed app.
- Never weaken signature requirements or edit TCC databases to bypass this check.
- Switching an old ad-hoc entry off/on can retain its obsolete code requirement.
  When logs confirm that mismatch after migration, quit the app and use the scoped
  `tccutil reset ScreenCapture local.screen-to-codex`, then reopen the unchanged
  signed bundle and let the user grant access again. Do not reset other apps.
- After macOS quits the app during permission changes, reopen the unchanged bundle.
  A global shortcut requires the menu-bar process to remain running.
- Permission setup must precede selection. Open Settings arms a bounded, one-shot
  native process-exit watcher; explicit cancellation disarms it. Do not cancel
  merely because a permission refresh succeeds: macOS may still be about to quit
  the owning process. Continue/Close cancels recovery when the user is ready.
- Verify actual capture after a signed rebuild, not just the signing requirement:
  the installed signed update captured successfully on 2026-09-17 at 15:38 +08:00.
