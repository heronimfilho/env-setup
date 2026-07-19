# Architecture

## Entrypoint

`setup.ps1` parses user intent, loads modules, handles management commands, resolves the plan, validates prerequisites, saves preferences, and invokes the task runner.

## Modules

- `EnvSetup.Core.ps1`: storage, state, generic helpers, and dependency ordering.
- `EnvSetup.Runtime.ps1`: output modes, logging, native-process heartbeat, timeout, and the interactive selector.
- `EnvSetup.Selection.ps1`: saved-plan validation and menu metadata.
- `EnvSetup.Progress.ps1`: task phases, results, summaries, error codes, and recovery guidance.
- `EnvSetup.Diagnostics.ps1`: doctor checks, status, exports, log access, and sanitized bundles.
- `EnvSetup.Update.ps1`: release-manifest validation and immutable updates.
- feature modules: Windows packages/settings, Git, VS Code, WSL, and shell configuration.

The progress runner is loaded last intentionally. Feature modules define tasks, while the runner owns their lifecycle.

## Task lifecycle

1. Resolve transitive dependencies.
2. Persist `checking` in task state.
3. Run `Detect` without changing the machine.
4. Skip when configured unless repair mode is active.
5. Persist `applying` and run `Apply`.
6. Persist `verifying` and run `Verify`.
7. Persist the result or a stable error code.
8. Include the task in the final execution summary.

## State and safety

Persistent data is stored under `%LOCALAPPDATA%\env-setup` and remains outside the repository so code updates do not remove plans, state, backups, or logs.

Inspection modes do not create storage, lock, plan, state, or log files. Configuration changes should be atomic, idempotent, and limited to managed sections.

## Update model

`release-manifest.json` publishes a semantic version, immutable commit, and archive SHA-256. The updater downloads the bootstrap from that commit, verifies the archive, backs up the current code, applies the snapshot, and restores the backup on failure.
