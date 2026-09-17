# Local app updates

- An enabled Screen Recording switch is not proof that the current binary is authorized.
  TCC logs can show a stored ad-hoc `cdhash` that differs from the running bundle.
- Re-signing after changing resources, including the icon, can change that identity too.
- Do not rebuild or re-sign an authorized app during permission diagnosis. Launch the
  existing bundle with `scripts/run.sh` and verify `hotkey.registered` in the logs.
- Routine builds must not overwrite an existing ad-hoc bundle. Use a stable signing
  certificate for repeated updates; explicit ad-hoc replacement needs a fresh grant.
- Never weaken signature requirements or edit TCC databases to bypass this check.
- After macOS quits the app during permission changes, reopen the unchanged bundle.
  A global shortcut requires the menu-bar process to remain running.
