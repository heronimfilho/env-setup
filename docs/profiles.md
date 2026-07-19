# Profiles and configuration

## Built-in profiles

### Core

Installs the baseline terminal, Git, GitHub CLI, Visual Studio Code, 7-Zip, WSL development tools, Zsh, NVM, Node.js LTS, and managed shell settings.

### Backend

Includes Core plus Docker Desktop, DBeaver, Bruno, the .NET SDK, AWS CLI, selected VS Code profiles, and backend-oriented configuration.

### Full

Includes every profile-based optional tool and development stack. Items that are deliberately opt-in only may still require explicit selection.

## Explicit task selection

```powershell
.\setup.ps1 -Include windows.git,git.windows-config,wsl.node
.\setup.ps1 -Profile Backend -Exclude windows.docker
```

Dependencies are added automatically. Excluding a required dependency is rejected rather than producing a partial configuration.

## Configuration files

Export the saved interactive plan:

```powershell
.\setup.ps1 -ExportConfig .\profiles\my-machine.json
```

Reuse it:

```powershell
.\setup.ps1 -Config .\profiles\my-machine.json
```

Command-line values take priority over values stored in the configuration file.

## Automation

```powershell
.\setup.ps1 `
  -Config .\profiles\my-machine.json `
  -NonInteractive `
  -SkipConfirmation `
  -OutputFormat Json `
  -NoColor
```

Interactive tasks must already be configured or the non-interactive run stops with a clear error.
