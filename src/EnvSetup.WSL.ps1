Set-StrictMode -Version Latest

function Get-SupportedWslDistributions {
    return @(
        'Ubuntu',
        'Ubuntu-24.04',
        'Ubuntu-22.04',
        'Debian',
        'kali-linux'
    )
}

function Test-WslDistributionSupported {
    param([Parameter(Mandatory = $true)][string]$Distribution)
    return (Get-SupportedWslDistributions) -contains $Distribution
}

function Get-WslBasePackageNames {
    return @(
        'build-essential',
        'ca-certificates',
        'curl',
        'git',
        'htop',
        'jq',
        'ripgrep',
        'shellcheck',
        'tree',
        'unzip',
        'zip'
    )
}

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

function Get-WslDistributionVersion {
    param([Parameter(Mandatory = $true)][string]$Distribution)

    if (-not (Test-CommandAvailable -Name 'wsl.exe')) {
        return $null
    }

    $result = Invoke-NativeCommand -FilePath 'wsl.exe' -ArgumentList @('--list', '--verbose') -AllowFailure -Quiet
    if ($result.ExitCode -ne 0) {
        return $null
    }

    foreach ($outputLine in $result.Output) {
        $line = ([string]$outputLine -replace "`0", '').Trim()
        if ($line.StartsWith('*')) {
            $line = $line.Substring(1).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $parts = @($line -split '\s+')
        if ($parts.Count -lt 3 -or $parts[0] -ne $Distribution) { continue }

        $version = $parts[$parts.Count - 1]
        if ($version -match '^[12]$') {
            return [int]$version
        }
    }

    return $null
}

function Test-WslDistributionInstalled {
    param([Parameter(Mandatory = $true)]$Context)
    return (Get-InstalledWslDistributions) -contains $Context.Options.WslDistribution
}

function Test-WslDistributionReady {
    param([Parameter(Mandatory = $true)]$Context)
    if (-not (Test-WslDistributionInstalled -Context $Context)) { return $false }
    return (Get-WslDistributionVersion -Distribution $Context.Options.WslDistribution) -eq 2
}

function Set-WslDistributionVersionTwo {
    param([Parameter(Mandatory = $true)]$Context)

    Invoke-NativeCommand -FilePath 'wsl.exe' -ArgumentList @(
        '--set-version', $Context.Options.WslDistribution, '2'
    ) | Out-Null
}

function Install-WslDistribution {
    param([Parameter(Mandatory = $true)]$Context)

    if (-not (Test-WslDistributionSupported -Distribution $Context.Options.WslDistribution)) {
        throw "Unsupported WSL distribution: $($Context.Options.WslDistribution)."
    }

    if (Test-WslDistributionInstalled -Context $Context) {
        $version = Get-WslDistributionVersion -Distribution $Context.Options.WslDistribution
        if ($version -eq 1) {
            Write-SetupMessage -Message "Converting $($Context.Options.WslDistribution) to WSL 2." -Level Info
            Set-WslDistributionVersionTwo -Context $Context
        }
        elseif ($version -ne 2) {
            throw "Could not determine the WSL version for $($Context.Options.WslDistribution)."
        }

        if (-not (Test-WslDistributionReady -Context $Context)) {
            throw "The distribution is installed but is not running on WSL 2: $($Context.Options.WslDistribution)."
        }
        return
    }

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

    if (Test-WslDistributionInstalled -Context $Context) {
        $version = Get-WslDistributionVersion -Distribution $Context.Options.WslDistribution
        if ($version -eq 1) {
            Set-WslDistributionVersionTwo -Context $Context
        }
    }

    if (-not (Test-WslDistributionReady -Context $Context)) {
        throw 'Restart Windows, then run .\setup.ps1 -Resume.'
    }
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

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $output
        Text     = ($output -join [Environment]::NewLine)
    }
}

function Test-WslDistributionInitialized {
    param([Parameter(Mandatory = $true)]$Context)

    if (-not (Test-WslDistributionReady -Context $Context)) { return $false }
    $result = Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('id', '-u') -AllowFailure -Quiet
    return $result.ExitCode -eq 0 -and $result.Text.Trim() -match '^\d+$' -and $result.Text.Trim() -ne '0'
}

function Initialize-WslDistribution {
    param([Parameter(Mandatory = $true)]$Context)

    if ($Context.Options.NonInteractive) {
        throw 'Linux user initialization requires an interactive terminal. Run setup without -NonInteractive, then resume.'
    }

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
    $arguments = @('env')
    if ($Context.Options.NonInteractive) {
        $arguments += 'ENV_SETUP_NONINTERACTIVE=1'
    }
    $arguments += @('bash', $wslPath)
    Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList $arguments | Out-Null
}

function Get-WslBasePackageValidationCommand {
    $packages = (Get-WslBasePackageNames) -join ' '
    return (@'
set -e
for package in __PACKAGES__; do
  status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)"
  test "$status" = "install ok installed"
done
test -d "$HOME/projects"
test -d "$HOME/bin"
'@ -replace '__PACKAGES__', $packages)
}

function Test-WslBasePackages {
    param([Parameter(Mandatory = $true)]$Context)
    if (-not (Test-WslDistributionInitialized -Context $Context)) { return $false }

    $result = Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @(
        'bash', '-lc', (Get-WslBasePackageValidationCommand)
    ) -AllowFailure -Quiet
    return $result.ExitCode -eq 0
}

function Install-WslBasePackages {
    param([Parameter(Mandatory = $true)]$Context)

    $sudoCommand = if ($Context.Options.NonInteractive) { 'sudo -n' } else { 'sudo' }
    $packages = (Get-WslBasePackageNames) -join ' '
    $command = (@'
set -Eeuo pipefail
__SUDO__ apt-get update
__SUDO__ env DEBIAN_FRONTEND=noninteractive apt-get install -y __PACKAGES__
mkdir -p "$HOME/projects" "$HOME/bin"
'@ -replace '__SUDO__', $sudoCommand) -replace '__PACKAGES__', $packages

    Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('bash', '-lc', $command) | Out-Null
}

function Get-WslGitConfigValue {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if (-not (Test-WslDistributionInitialized -Context $Context)) { return $null }
    $result = Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @(
        'git', 'config', '--global', '--get', $Key
    ) -AllowFailure -Quiet
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

    $backupCommand = 'if test -f "$HOME/.gitconfig"; then mkdir -p "$HOME/.env-setup/backups"; cp "$HOME/.gitconfig" "$HOME/.env-setup/backups/gitconfig-$(date +%Y%m%d-%H%M%S)-$$.bak"; fi'
    Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('bash', '-lc', $backupCommand) -Quiet | Out-Null

    foreach ($item in ([ordered]@{
        'user.name' = $Context.Options.GitName
        'user.email' = $Context.Options.GitEmail
        'init.defaultBranch' = 'main'
        'fetch.prune' = 'true'
        'pull.ff' = 'only'
        'core.editor' = 'code --wait'
    }).GetEnumerator()) {
        Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @(
            'git', 'config', '--global', $item.Key, [string]$item.Value
        ) -Quiet | Out-Null
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

function Convert-ToPosixSingleQuotedString {
    param([Parameter(Mandatory = $true)][string]$Value)

    $singleQuoteEscape = "'" + "\" + "'" + "'"
    return "'" + $Value.Replace("'", $singleQuoteEscape) + "'"
}

function Get-WslGcmHelperValue {
    param([Parameter(Mandatory = $true)]$Context)

    $windowsPath = Get-GitCredentialManagerWindowsPath
    if ([string]::IsNullOrWhiteSpace($windowsPath)) { return $null }
    $wslPath = Convert-ToWslPath -Context $Context -WindowsPath $windowsPath
    return Convert-ToPosixSingleQuotedString -Value $wslPath
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
    Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @(
        'git', 'config', '--global', 'credential.helper', $helper
    ) -Quiet | Out-Null
}

function Test-WslZshConfiguration {
    param([Parameter(Mandatory = $true)]$Context)
    if (-not (Test-WslDistributionInitialized -Context $Context)) { return $false }
    $command = 'command -v zsh >/dev/null && test -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" && grep -q ''^ZSH_THEME="dracula"'' "$HOME/.zshrc" && grep -q ''zsh-autosuggestions'' "$HOME/.zshrc"'
    $result = Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @('bash', '-lc', $command) -AllowFailure -Quiet
    return $result.ExitCode -eq 0
}

function Get-WslNodeValidationCommand {
    return @'
export NVM_DIR="$HOME/.nvm"
test -s "$NVM_DIR/nvm.sh"
. "$NVM_DIR/nvm.sh"
test "$(nvm --version)" = "0.40.4"
nvm alias default | grep -Fq 'default -> lts/*'
current_version="$(nvm current)"
remote_lts_version="$(nvm version-remote --lts 2>/dev/null || true)"
test -n "$remote_lts_version"
test "$remote_lts_version" != "N/A"
test "$current_version" = "$remote_lts_version"
test "$(node --version)" = "$current_version"
npm --version >/dev/null
'@
}

function Test-WslNodeConfiguration {
    param([Parameter(Mandatory = $true)]$Context)
    if (-not (Test-WslDistributionInitialized -Context $Context)) { return $false }
    $result = Invoke-WslCommand -Distribution $Context.Options.WslDistribution -ArgumentList @(
        'bash', '-lc', (Get-WslNodeValidationCommand)
    ) -AllowFailure -Quiet
    return $result.ExitCode -eq 0
}

function Get-WslTasks {
    return @(
        [pscustomobject]@{
            Id = 'wsl.install'; Name = 'Install WSL 2 and the Linux distribution'; Category = 'WSL'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $true; Dependencies = @()
            Detect = { param($Context) Test-WslDistributionReady -Context $Context }
            Apply = { param($Context) Install-WslDistribution -Context $Context }
            Verify = { param($Context) Test-WslDistributionReady -Context $Context }
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
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $false; Dependencies = @('wsl.base', 'windows.vscode')
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
