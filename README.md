# env-setup

## Installs

Core:

- PowerShell 7
- Windows Terminal
- Git for Windows and Git Credential Manager
- GitHub CLI
- Visual Studio Code
- 7-Zip
- WSL 2 and a Linux distribution
- Linux development tools
- Zsh, Oh My Zsh and Dracula
- NVM and the latest Node.js LTS

Optional:

- SSH key and GitHub authentication
- Docker Desktop
- PowerToys
- DBeaver
- Bruno or Postman
- .NET SDK
- AWS CLI
- Terraform
- kubectl and Helm
- Developer Mode
- Windows Sandbox
- VS Code profiles for Node.js, .NET, Delphi and DevOps

## Options

```powershell
.\setup.ps1
.\setup.ps1 -Profile Core
.\setup.ps1 -Profile Backend
.\setup.ps1 -Profile Full
.\setup.ps1 -Config .\profiles\custom.example.json
.\setup.ps1 -Include windows.git,wsl.node
.\setup.ps1 -Exclude windows.docker
.\setup.ps1 -WslDistribution Ubuntu-24.04
.\setup.ps1 -WslWebDownload
.\setup.ps1 -DryRun
.\setup.ps1 -Check
.\setup.ps1 -Repair
.\setup.ps1 -Resume
```

Supported WSL distributions: `Ubuntu`, `Ubuntu-24.04`, `Ubuntu-22.04`, `Debian`, `kali-linux`.

Non-interactive Git configuration:

```powershell
.\setup.ps1 `
  -Include windows.git,git.windows-config,git.windows-gcm `
  -NonInteractive `
  -GitName "Your Name" `
  -GitEmail "you@example.com"
```

## Zsh

Theme: `dracula`

Plugins:

- `git`
- `sudo`
- `extract`
- `colored-man-pages`
- `zsh-autosuggestions`
- `zsh-syntax-highlighting`

Node.js:

- NVM `v0.40.4`
- latest Node.js LTS
- latest compatible npm
- default alias `lts/*`
- Corepack when available

## Install

Run PowerShell as Administrator.

Without Git:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
$commit = "c8c8d8d8a5ec4579a469719e0735fd42172cc1f3"
$archiveSha256 = "c00cda95717cead331b1784f773df96557c174b5da2b5adfd5d370dfa8a22457"
$bootstrap = Join-Path $env:TEMP "env-setup-bootstrap-$commit.ps1"
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/heronimfilho/env-setup/$commit/bootstrap.ps1" `
  -OutFile $bootstrap
& $bootstrap -Commit $commit -ArchiveSha256 $archiveSha256
```

With Git:

```powershell
git clone https://github.com/heronimfilho/env-setup.git
cd env-setup
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
```

After a restart or interrupted task:

```powershell
cd $HOME\env-setup
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1 -Resume
```
