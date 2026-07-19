# Contributing

Thank you for improving `env-setup`.

## Development workflow

1. Create a focused branch from `main`.
2. Keep each change small enough to review independently.
3. Add or update tests for behavioral changes.
4. Run the relevant PowerShell and shell tests.
5. Open a pull request describing the user impact, implementation, risks, and validation.

## Local validation

On Windows PowerShell 5.1:

```powershell
Get-ChildItem .\tests\*.test.ps1 | ForEach-Object { & $_.FullName }
```

On Linux:

```bash
bash -n configure-zsh.sh install-node.sh tests/*.sh
shellcheck configure-zsh.sh install-node.sh tests/*.sh
bash tests/configure-zsh.test.sh
bash tests/node.test.sh
```

## Adding a task

Every task must have a stable ID, user-facing name, category, profiles, dependency list, detection operation, apply operation, and verification operation. Detection and verification must be idempotent and must not modify the machine.

See [`docs/adding-a-task.md`](docs/adding-a-task.md) for the complete checklist.

## Safety expectations

- Never store tokens, passwords, passphrases, or private keys.
- Preserve unrelated user configuration.
- Back up files before modifying managed sections.
- Keep `-Check` and `-DryRun` read-only.
- Pin remote downloads to immutable versions and validate hashes when possible.
- Provide a recovery path for interrupted operations.

## Pull requests

Use squash merge. A pull request is ready only when all required checks pass and every review conversation is resolved.
