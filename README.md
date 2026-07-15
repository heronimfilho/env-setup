# env-setup

## Installs

- WSL 2
- Linux distribution
- Zsh
- Oh My Zsh
- Dracula theme
- Zsh autosuggestions
- Zsh syntax highlighting

## Options

Default distribution: `Ubuntu`

```powershell
.\install-wsl.ps1 -Distribution Ubuntu
.\install-wsl.ps1 -Distribution Ubuntu-24.04
.\install-wsl.ps1 -Distribution Ubuntu-22.04
.\install-wsl.ps1 -Distribution Debian
.\install-wsl.ps1 -Distribution kali-linux
```

Use `-WebDownload` when Microsoft Store installation is unavailable:

```powershell
.\install-wsl.ps1 -Distribution Ubuntu -WebDownload
```

Available distributions:

```powershell
wsl --list --online
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

## Install

Run PowerShell as Administrator:

```powershell
git clone https://github.com/heronimfilho/env-setup.git
cd env-setup
Set-ExecutionPolicy -Scope Process Bypass
.\install-wsl.ps1 -Distribution Ubuntu
```

Restart Windows, launch the distribution once, create the Linux user, then open PowerShell normally:

```powershell
cd env-setup
Set-ExecutionPolicy -Scope Process Bypass
.\configure-zsh.ps1 -Distribution Ubuntu
```
