Set-StrictMode -Version Latest

function Get-InstalledWslDistributions {
    if (-not (Test-CommandAvailable -Name 'wsl.exe')) {
        return @()
    }

    $result = Invoke-NativeCommand -FilePath 'wsl.exe' -ArgumentList @('--list', '--quiet') -AllowFailure -Quiet
    if ($result.ExitCode -ne 0) {
        return @()
    }

    return @(
        $result.Output |
            ForEach-Object { ([string]$_ -replace "`0", '').Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Test-WslDistributionInstalled {
    param([Parameter(Mandatory = $true)]$Context)
    return (Get-InstalledWslDistributions) -contains $Context.Options.WslDistribution
}

function Install-WslDistribution {
    param([Parameter(Mandatory = $true)]$Context)

    $arguments = @(
        '--install',
        '--distribution', $Context.Options.WslDistribution,
        '--no-launch'
    )
    if ($Context.Options.WslWebDownload) {
        $arguments += '--web-download'
    }

    $result = Invoke-NativeCommand -FilePath 'wsl.exe' -ArgumentList $arguments -AllowFailure
    if ($result.ExitCode -notin @(0, 3010)) {
        throw "WSL installation failed with exit code $($result.ExitCode)."
    }

    if (-not (Test-WslDistributionInstalled -Context $Context)) {
        throw 'Restart Windows, then run .\setup.ps1 -Resume.'
    }
}

function Get-WslDistributionDefaultUid {
    param([Parameter(Mandatory = $true)][string]$Distribution)

    $registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path -LiteralPath $registryPath)) {
        return $null
    }

    $entry = Get-ChildItem -LiteralPath $registryPath -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath } |
        Where-Object { $_.DistributionName -eq $Distribution } |
        Select-Object -First 1

    if ($null -eq $entry) { return $null }
    $property = $entry.PSObject.Properties['DefaultUid']
    if ($null -eq $property) { return $null }
    return [uint32]$property.Value
}

function Invoke-WslCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Distribution,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [switch]$AllowFailure,
        [switch]$Quiet
    )

    if (-not (Test-CommandAvailable -Name 'wsl.exe')) {
        throw 'wsl.exe is not available.'
    }

    $output = @(& wsl.exe --distribution $Distribution --exec @ArgumentList 2>&1)
    $exitCode = $LASTEXITCODE
    if (-not $Quiet) { $output | ForEach-Object { Write-Host $_ } }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "WSL command exited with code $exitCode.`n$($output -join [Environment]::NewLine)"
    }

    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output; Text = ($output -join [Environment]::NewLine) }
}

function Test-WslDistributionInitialized {
    param([Parameter(Mandatory = $true)]$Context)

    if (-not (Test-WslDistributionInstalled -Context $Context)) { return $false }
    $defaultUid = Get-WslDistributionDefaultUid -Distribution $Context.Options.WslDistribution
    if ($null -eq $defaultUid -or $defaultUid -eq 0) { return $false }

    $result = Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('id', '-u') -AllowFailure -Quiet
    return $result.ExitCode -eq 0 -and $result.Text.Trim() -ne '0'
}

function Initialize-WslDistribution {
    param([Parameter(Mandatory = $true)]$Context)

    Write-SetupMessage -Message "Complete the Linux user creation for $($Context.Options.WslDistribution), then exit the distribution." -Level Warning
    & wsl.exe --distribution $Context.Options.WslDistribution
    if ($LASTEXITCODE -ne 0) {
        throw "The distribution exited with code $LASTEXITCODE."
    }

    if (-not (Test-WslDistributionInitialized -Context $Context)) {
        throw 'The distribution still does not have a non-root default user. Complete initialization and run .\setup.ps1 -Resume.'
    }
}

function Convert-ToWslPath {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$WindowsPath
    )

    $result = Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('wslpath', '-a', '-u', $WindowsPath) -Quiet
    $path = $result.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "Could not convert the Windows path for WSL: $WindowsPath"
    }
    return $path
}

function Invoke-WslProjectScript {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$ScriptName
    )

    $windowsPath = Join-Path $Context.ProjectRoot $ScriptName
    if (-not (Test-Path -LiteralPath $windowsPath -PathType Leaf)) {
        throw "Script not found: $ScriptName"
    }

    $wslPath = Convert-ToWslPath -Context $Context -WindowsPath $windowsPath
    Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('bash', $wslPath) | Out-Null
}

function Test-WslBasePackages {
    param([Parameter(Mandatory = $true)]$Context)
    if (-not (Test-WslDistributionInitialized -Context $Context)) { return $false }

    $command = 'command -v git >/dev/null && command -v curl >/dev/null && command -v jq >/dev/null && command -v rg >/dev/null && command -v shellcheck >/dev/null'
    $result = Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('bash', '-lc', $command) -AllowFailure -Quiet
    return $result.ExitCode -eq 0
}

function Install-WslBasePackages {
    param([Parameter(Mandatory = $true)]$Context)

    $command = @'
set -Eeuo pipefail
sudo apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential \
  ca-certificates \
  curl \
  git \
  htop \
  jq \
  ripgrep \
  shellcheck \
  tree \
  unzip \
  zip
mkdir -p "$HOME/projects" "$HOME/bin"
'@
    Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('bash', '-lc', $command) | Out-Null
}

function Get-WslGitConfigValue {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if (-not (Test-WslDistributionInitialized -Context $Context)) { return $null }
    $result = Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('git', 'config', '--global', '--get', $Key) -AllowFailure -Quiet
    if ($result.ExitCode -ne 0) { return $null }
    return $result.Text.Trim()
}

function Test-WslGitConfiguration {
    param([Parameter(Mandatory = $true)]$Context)

    $expected = [ordered]@{
        'user.name'          = $Context.Options.GitName
        'user.email'         = $Context.Options.GitEmail
        'init.defaultBranch' = 'main'
        'fetch.prune'        = 'true'
        'pull.ff'            = 'only'
        'core.editor'        = 'code --wait'
    }

    foreach ($item in $expected.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$item.Value)) { return $false }
        if ((Get-WslGitConfigValue -Context $Context -Key $item.Key) -ne [string]$item.Value) { return $false }
    }
    return $true
}

function Set-WslGitConfiguration {
    param([Parameter(Mandatory = $true)]$Context)

    foreach ($item in ([ordered]@{
        'user.name' = $Context.Options.GitName
        'user.email' = $Context.Options.GitEmail
        'init.defaultBranch' = 'main'
        'fetch.prune' = 'true'
        'pull.ff' = 'only'
        'core.editor' = 'code --wait'
    }).GetEnumerator()) {
        Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('git', 'config', '--global', $item.Key, [string]$item.Value) -Quiet | Out-Null
    }
}

function Get-GitCredentialManagerWindowsPath {
    $candidates = New-Object System.Collections.Generic.List[string]
    $gitCommand = Get-Command 'git.exe' -ErrorAction SilentlyContinue
    if ($null -ne $gitCommand) {
        $candidates.Add((Join-Path (Split-Path -Parent $gitCommand.Source) 'git-credential-manager.exe'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates.Add((Join-Path $env:ProgramFiles 'Git\mingw64\bin\git-credential-manager.exe'))
        $candidates.Add((Join-Path $env:ProgramFiles 'Git\cmd\git-credential-manager.exe'))
    }
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Git\mingw64\bin\git-credential-manager.exe'))
    }

    return $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

function Get-WslGcmHelperValue {
    param([Parameter(Mandatory = $true)]$Context)

    $windowsPath = Get-GitCredentialManagerWindowsPath
    if ([string]::IsNullOrWhiteSpace($windowsPath)) { return $null }
    $wslPath = Convert-ToWslPath -Context $Context -WindowsPath $windowsPath
    return $wslPath -replace ' ', '\ '
}

function Test-WslGcmConfiguration {
    param([Parameter(Mandatory = $true)]$Context)
    $expected = Get-WslGcmHelperValue -Context $Context
    if ([string]::IsNullOrWhiteSpace($expected)) { return $false }
    return (Get-WslGitConfigValue -Context $Context -Key 'credential.helper') -eq $expected
}

function Set-WslGcmConfiguration {
    param([Parameter(Mandatory = $true)]$Context)
    $helper = Get-WslGcmHelperValue -Context $Context
    if ([string]::IsNullOrWhiteSpace($helper)) {
        throw 'Git Credential Manager was not found in the Git for Windows installation.'
    }
    Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('git', 'config', '--global', 'credential.helper', $helper) -Quiet | Out-Null
}

function Test-WslZshConfiguration {
    param([Parameter(Mandatory = $true)]$Context)
    if (-not (Test-WslDistributionInitialized -Context $Context)) { return $false }
    $command = 'command -v zsh >/dev/null && test -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" && grep -q ''^ZSH_THEME="dracula"'' "$HOME/.zshrc" && grep -q ''zsh-autosuggestions'' "$HOME/.zshrc"'
    $result = Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('bash', '-lc', $command) -AllowFailure -Quiet
    return $result.ExitCode -eq 0
}

function Test-WslNodeConfiguration {
    param([Parameter(Mandatory = $true)]$Context)
    if (-not (Test-WslDistributionInitialized -Context $Context)) { return $false }
    $command = 'export NVM_DIR="$HOME/.nvm"; test -s "$NVM_DIR/nvm.sh" && . "$NVM_DIR/nvm.sh" && nvm current | grep -vq ''none'' && node --version >/dev/null && npm --version >/dev/null'
    $result = Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('bash', '-lc', $command) -AllowFailure -Quiet
    return $result.ExitCode -eq 0
}

function Get-WslTasks {
    return @(
        [pscustomobject]@{
            Id = 'wsl.install'; Name = 'Install WSL 2 and the Linux distribution'; Category = 'WSL'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $true; Dependencies = @()
            Detect = { param($Context) Test-WslDistributionInstalled -Context $Context }
            Apply = { param($Context) Install-WslDistribution -Context $Context }
            Verify = { param($Context) Test-WslDistributionInstalled -Context $Context }
        }
        [pscustomobject]@{
            Id = 'wsl.initialize'; Name = 'Initialize the Linux user'; Category = 'WSL'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $false; Dependencies = @('wsl.install')
            Detect = { param($Context) Test-WslDistributionInitialized -Context $Context }
            Apply = { param($Context) Initialize-WslDistribution -Context $Context }
            Verify = { param($Context) Test-WslDistributionInitialized -Context $Context }
        }
        [pscustomobject]@{
            Id = 'wsl.base'; Name = 'Install Linux development tools'; Category = 'WSL'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $false; Dependencies = @('wsl.initialize')
            Detect = { param($Context) Test-WslBasePackages -Context $Context }
            Apply = { param($Context) Install-WslBasePackages -Context $Context }
            Verify = { param($Context) Test-WslBasePackages -Context $Context }
        }
        [pscustomobject]@{
            Id = 'git.wsl-config'; Name = 'Configure Git inside WSL'; Category = 'Git and GitHub'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $false; Dependencies = @('wsl.base')
            Detect = { param($Context) Test-WslGitConfiguration -Context $Context }
            Apply = { param($Context) Set-WslGitConfiguration -Context $Context }
            Verify = { param($Context) Test-WslGitConfiguration -Context $Context }
        }
        [pscustomobject]@{
            Id = 'git.wsl-gcm'; Name = 'Share Git Credential Manager with WSL'; Category = 'Git and GitHub'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $false; Dependencies = @('windows.git', 'git.windows-gcm', 'git.wsl-config')
            Detect = { param($Context) Test-WslGcmConfiguration -Context $Context }
            Apply = { param($Context) Set-WslGcmConfiguration -Context $Context }
            Verify = { param($Context) Test-WslGcmConfiguration -Context $Context }
        }
        [pscustomobject]@{
            Id = 'wsl.zsh'; Name = 'Configure Zsh and Oh My Zsh'; Category = 'WSL'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $false; Dependencies = @('wsl.base')
            Detect = { param($Context) Test-WslZshConfiguration -Context $Context }
            Apply = { param($Context) Invoke-WslProjectScript -Context $Context -ScriptName 'configure-zsh.sh' }
            Verify = { param($Context) Test-WslZshConfiguration -Context $Context }
        }
        [pscustomobject]@{
            Id = 'wsl.node'; Name = 'Install NVM and Node.js LTS'; Category = 'Development stacks'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $false; Dependencies = @('wsl.zsh')
            Detect = { param($Context) Test-WslNodeConfiguration -Context $Context }
            Apply = { param($Context) Invoke-WslProjectScript -Context $Context -ScriptName 'install-node.sh' }
            Verify = { param($Context) Test-WslNodeConfiguration -Context $Context }
        }
    )
}
