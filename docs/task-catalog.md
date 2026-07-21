# Task catalog

Use `setup.ps1 -ListTasks` for the authoritative machine-readable catalog. Task IDs are stable and can be passed to `-Include` and `-Exclude`.

## Windows applications

| Task ID | Component | Default | Profiles |
| --- | --- | --- | --- |
| `windows.powershell` | PowerShell 7 | Yes | Core, Backend, Full |
| `windows.terminal` | Windows Terminal | Yes | Core, Backend, Full |
| `windows.git` | Git for Windows | Yes | Core, Backend, Full |
| `windows.github-cli` | GitHub CLI | Yes | Core, Backend, Full |
| `windows.vscode` | Visual Studio Code | Yes | Core, Backend, Full |
| `windows.7zip` | 7-Zip | Yes | Core, Backend, Full |
| `windows.powertoys` | PowerToys | No | Full |
| `windows.docker` | Docker Desktop | No | Backend, Full |
| `windows.dbeaver` | DBeaver | No | Backend, Full |
| `windows.bruno` | Bruno | No | Backend, Full |
| `windows.postman` | Postman | No | Full |
| `windows.dotnet` | .NET SDK 10 | No | Backend, Full |
| `windows.aws-cli` | AWS CLI | No | Backend, Full |
| `windows.terraform` | Terraform | No | Full |
| `windows.kubectl` | kubectl | No | Full |
| `windows.helm` | Helm | No | Full |

## Git and GitHub

| Task ID | Component | Default | Profiles |
| --- | --- | --- | --- |
| `git.windows-config` | Configure Git for Windows | Yes | Core, Backend, Full |
| `git.windows-gcm` | Configure Git Credential Manager | Yes | Core, Backend, Full |
| `github.authenticate` | Authenticate GitHub CLI | No | Full |
| `ssh.windows-key` | Generate a Windows SSH key | No | Full |
| `ssh.github-upload` | Upload the Windows SSH key to GitHub | No | Full |
| `git.wsl-config` | Configure Git inside WSL | Yes | Core, Backend, Full |
| `git.wsl-gcm` | Share Git Credential Manager with WSL | Yes | Core, Backend, Full |

## Visual Studio Code

| Task ID | Component | Default | Profiles |
| --- | --- | --- | --- |
| `vscode.settings` | Merge managed settings | Yes | Core, Backend, Full |
| `vscode.extensions-base` | Install base extensions | Yes | Core, Backend, Full |
| `vscode.extensions-node` | Create the Node.js extension profile | No | Backend, Full |
| `vscode.extensions-dotnet` | Create the .NET extension profile | No | Backend, Full |
| `vscode.extensions-delphi` | Create the Delphi extension profile | No | Full |
| `vscode.extensions-devops` | Create the DevOps extension profile | No | Full |

## WSL and Linux

| Task ID | Component | Default | Profiles |
| --- | --- | --- | --- |
| `wsl.install` | Install WSL 2 and the selected distribution | Yes | Core, Backend, Full |
| `wsl.initialize` | Initialize the Linux user | Yes | Core, Backend, Full |
| `wsl.packages` | Install Linux development tools | Yes | Core, Backend, Full |
| `wsl.zsh` | Configure Zsh, Oh My Zsh, and Dracula | Yes | Core, Backend, Full |
| `wsl.node` | Install NVM and Node.js LTS | Yes | Core, Backend, Full |

## Shell configuration

| Task ID | Component | Default | Profiles |
| --- | --- | --- | --- |
| `shell.powershell` | Configure the PowerShell 7 profile | Yes | Core, Backend, Full |
| `shell.terminal` | Configure Windows Terminal | Yes | Core, Backend, Full |

## Windows settings

| Task ID | Component | Default | Profiles |
| --- | --- | --- | --- |
| `windows.show-extensions` | Show file name extensions | Yes | Core, Backend, Full |
| `windows.show-hidden` | Show hidden files | Yes | Core, Backend, Full |
| `windows.long-paths` | Enable long Win32 paths | Yes | Core, Backend, Full |
| `windows.developer-mode` | Enable Developer Mode | No | Backend, Full |
| `windows.sandbox` | Enable Windows Sandbox | No | Full |

Dependencies are resolved automatically. Excluding a task required by another selected task is rejected before any changes begin.
