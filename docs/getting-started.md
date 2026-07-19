# Getting started

## Requirements

- Windows 10 build 19041 or newer, or Windows 11;
- Windows PowerShell 5.1 or PowerShell 7;
- an administrator session for system-level tasks;
- App Installer with WinGet;
- internet access to GitHub, Microsoft downloads, and the WinGet CDN;
- firmware virtualization for WSL 2 and Windows Sandbox.

Run the preflight before installation:

```powershell
.\setup.ps1 -Doctor
```

## Interactive installation

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
```

The selector remembers confirmed choices. Use the keyboard shortcuts shown above the list to apply a profile, restore defaults, or search.

Before changes begin, the CLI presents the selected task count, automatic dependencies, categories, interactive operations, and whether a restart may be required.

## Profiles

```powershell
.\setup.ps1 -Profile Core
.\setup.ps1 -Profile Backend
.\setup.ps1 -Profile Full
```

Use `-DryRun` to preview changes and `-Check` to inspect the current machine without creating state or logs.

## Resume after interruption

```powershell
.\setup.ps1 -Resume
```

Every task is detected again before it is retried. Completed and already-configured tasks are skipped unless `-Repair` is supplied.

## Useful administrative commands

```powershell
.\setup.ps1 -Status
.\setup.ps1 -ListTasks
.\setup.ps1 -ExportConfig .\my-profile.json
.\setup.ps1 -CollectDiagnostics
.\setup.ps1 -ShowLastLog
.\setup.ps1 -Update
```

For scripts and CI systems, add `-OutputFormat Json -NoColor -NonInteractive`.
