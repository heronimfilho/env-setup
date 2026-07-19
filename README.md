# env-setup

[![Validate](https://github.com/heronimfilho/env-setup/actions/workflows/validate.yml/badge.svg)](https://github.com/heronimfilho/env-setup/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A resumable, observable, and idempotent Windows development-environment installer built with PowerShell, WinGet, and WSL.

## Highlights

- interactive checklist with remembered selections and Core, Backend, and Full shortcuts;
- detection, apply, and verification phases for every task;
- live heartbeat, elapsed timing, stable error codes, execution logs, and final summaries;
- safe resume and repair after failures, restarts, or interrupted installers;
- read-only check and dry-run modes;
- Windows, Git/GitHub, Visual Studio Code, WSL, Zsh, NVM, Node.js, cloud, and infrastructure tooling;
- preflight doctor, status reporting, plan export, sanitized diagnostics, and immutable self-update;
- text, no-color, and JSON-lines output for humans and automation;
- immutable bootstrap snapshots validated with SHA-256.

## Quick start

Open **Windows PowerShell as Administrator**.

```powershell
Set-ExecutionPolicy -Scope Process Bypass

$commit = "4d821a0080b467e01f4570f5f65a3c2a45fc54c2"
$archiveSha256 = "1a45b9402918d934f511d9ee840b0d5e58426649b5db0f668c7003ce666ffa65"
$bootstrap = Join-Path $env:TEMP "env-setup-bootstrap-$commit.ps1"

Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/heronimfilho/env-setup/$commit/bootstrap.ps1" `
  -OutFile $bootstrap

& $bootstrap -Commit $commit -ArchiveSha256 $archiveSha256
```

The pinned values above are updated only after the corresponding snapshot passes the complete validation workflow.

With Git already installed:

```powershell
git clone https://github.com/heronimfilho/env-setup.git
cd env-setup
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
```

## Before installing

Run the preflight diagnostics:

```powershell
.\setup.ps1 -Doctor
```

The doctor checks Windows compatibility, elevation, execution policy, WinGet, disk space, pending restart, firmware virtualization, WSL, and required network endpoints.

## Common commands

```powershell
# Interactive setup; confirmed choices are remembered
.\setup.ps1

# Built-in profiles
.\setup.ps1 -Profile Core
.\setup.ps1 -Profile Backend
.\setup.ps1 -Profile Full

# Inspect or preview without changing the machine
.\setup.ps1 -Check
.\setup.ps1 -Profile Backend -DryRun

# Continue after a failure or restart
.\setup.ps1 -Resume

# Reapply configured tasks
.\setup.ps1 -Resume -Repair

# Administration and support
.\setup.ps1 -Status
.\setup.ps1 -ListTasks
.\setup.ps1 -ExportConfig .\profiles\my-machine.json
.\setup.ps1 -ShowLastLog
.\setup.ps1 -CollectDiagnostics
.\setup.ps1 -Update

# Machine-readable automation
.\setup.ps1 -Profile Backend -NonInteractive -SkipConfirmation -OutputFormat Json -NoColor
```

Use `Get-Help .\setup.ps1 -Full` for parameter and example documentation.

## Runtime experience

A task reports its position, active operation, native-process heartbeat, phase timing, final result, and a stable error code when it fails.

```text
[1/36] [windows.powershell] PowerShell 7
  Checking WinGet package state for PowerShell 7 (Microsoft.PowerShell)...
    Still working - 10 seconds elapsed (PID 8420).
  State check finished in 12.4 s.
  Current state: missing or incomplete.
  Installing PowerShell 7 with WinGet (Microsoft.PowerShell)...
```

The final summary includes completed, already-configured, missing, planned, and failed counts, total duration, restart status, log path, and the exact resume command.

## Installed components

Core components include PowerShell 7, Windows Terminal, Git, Git Credential Manager, GitHub CLI, Visual Studio Code, 7-Zip, WSL 2, Linux development tools, Zsh, Oh My Zsh, Dracula, NVM, and the latest Node.js LTS.

Optional selections include Docker Desktop, PowerToys, DBeaver, Bruno, Postman, .NET SDK, AWS CLI, Terraform, kubectl, Helm, Developer Mode, Windows Sandbox, GitHub authentication, SSH setup, and VS Code extension profiles for Node.js, .NET, Delphi, and DevOps.

## State, logs, and recovery

Persistent runtime data is stored outside the repository:

```text
%LOCALAPPDATA%\env-setup\
  plan.json
  state.json
  backups\
  logs\
```

`-Check` and `-DryRun` do not create or modify these files. See [`docs/recovery.md`](docs/recovery.md) for interruption, restart, repair, timeout, and diagnostics guidance.

## Documentation

- [Getting started](docs/getting-started.md)
- [Profiles and configuration](docs/profiles.md)
- [Recovery and troubleshooting](docs/recovery.md)
- [Architecture](docs/architecture.md)
- [Adding a task](docs/adding-a-task.md)
- [Changelog](docs/changelog.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## Security

Review scripts before executing system-level automation. Bootstrap and update archives are pinned to immutable commits and validated with SHA-256. Secrets, tokens, passwords, passphrases, and private keys are not persisted. Diagnostic bundles are sanitized and should still be reviewed before sharing.

## License

[MIT](LICENSE)
