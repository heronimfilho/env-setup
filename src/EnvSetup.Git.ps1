Set-StrictMode -Version Latest

function Get-GitConfigValue {
    param([Parameter(Mandatory = $true)][string]$Key)

    if (-not (Test-CommandAvailable -Name 'git.exe')) {
        return $null
    }

    $result = Invoke-NativeCommand -FilePath 'git.exe' -ArgumentList @('config', '--global', '--get', $Key) -AllowFailure -Quiet
    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Text)) {
        return $null
    }

    return $result.Text.Trim()
}

function Set-GitConfigValue {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    Invoke-NativeCommand -FilePath 'git.exe' -ArgumentList @('config', '--global', $Key, $Value) -Quiet | Out-Null
}

function Backup-GitConfig {
    param([Parameter(Mandatory = $true)]$Context)

    $source = Join-Path $HOME '.gitconfig'
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        return
    }

    $backupDirectory = Join-Path $Context.Paths.RootPath 'backups'
    $destination = Join-Path $backupDirectory ("gitconfig-{0}.bak" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Test-WindowsGitConfiguration {
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
        if ([string]::IsNullOrWhiteSpace([string]$item.Value)) {
            return $false
        }
        if ((Get-GitConfigValue -Key $item.Key) -ne [string]$item.Value) {
            return $false
        }
    }

    return $true
}

function Set-WindowsGitConfiguration {
    param([Parameter(Mandatory = $true)]$Context)

    if ([string]::IsNullOrWhiteSpace($Context.Options.GitName)) {
        throw 'Git user name is required.'
    }
    if ([string]::IsNullOrWhiteSpace($Context.Options.GitEmail)) {
        throw 'Git email is required.'
    }

    Backup-GitConfig -Context $Context
    Set-GitConfigValue -Key 'user.name' -Value $Context.Options.GitName
    Set-GitConfigValue -Key 'user.email' -Value $Context.Options.GitEmail
    Set-GitConfigValue -Key 'init.defaultBranch' -Value 'main'
    Set-GitConfigValue -Key 'fetch.prune' -Value 'true'
    Set-GitConfigValue -Key 'pull.ff' -Value 'only'
    Set-GitConfigValue -Key 'core.editor' -Value 'code --wait'
}

function Test-GitCredentialManagerConfigured {
    if (-not (Test-CommandAvailable -Name 'git.exe')) {
        return $false
    }

    $version = Invoke-NativeCommand -FilePath 'git.exe' -ArgumentList @('credential-manager', '--version') -AllowFailure -Quiet
    if ($version.ExitCode -ne 0) {
        return $false
    }

    $helpers = Invoke-NativeCommand -FilePath 'git.exe' -ArgumentList @('config', '--global', '--get-all', 'credential.helper') -AllowFailure -Quiet
    return $helpers.Text -match 'manager'
}

function Set-GitCredentialManager {
    Invoke-NativeCommand -FilePath 'git.exe' -ArgumentList @('credential-manager', 'configure') -Quiet | Out-Null
}

function Test-GitHubCliAuthenticated {
    if (-not (Test-CommandAvailable -Name 'gh.exe')) {
        return $false
    }

    $result = Invoke-NativeCommand -FilePath 'gh.exe' -ArgumentList @('auth', 'status', '--hostname', 'github.com') -AllowFailure -Quiet
    return $result.ExitCode -eq 0
}

function Connect-GitHubCli {
    Invoke-NativeCommand -FilePath 'gh.exe' -ArgumentList @(
        'auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--web'
    ) | Out-Null
}

function Get-WindowsSshKeyPath {
    return Join-Path (Join-Path $HOME '.ssh') 'id_ed25519'
}

function Test-WindowsSshKey {
    $privateKey = Get-WindowsSshKeyPath
    return (Test-Path -LiteralPath $privateKey -PathType Leaf) -and (Test-Path -LiteralPath "$privateKey.pub" -PathType Leaf)
}

function New-WindowsSshKey {
    param([Parameter(Mandatory = $true)]$Context)

    if (-not (Test-CommandAvailable -Name 'ssh-keygen.exe')) {
        throw 'OpenSSH Client is required to generate an SSH key.'
    }

    $keyPath = Get-WindowsSshKeyPath
    if (Test-Path -LiteralPath $keyPath -PathType Leaf) {
        throw "An SSH private key already exists at $keyPath. It will not be overwritten."
    }

    $directory = Split-Path -Parent $keyPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Write-SetupMessage -Message 'ssh-keygen will ask for an optional passphrase. The passphrase is not stored by env-setup.' -Level Info
    & ssh-keygen.exe -t ed25519 -C $Context.Options.GitEmail -f $keyPath
    if ($LASTEXITCODE -ne 0) {
        throw "ssh-keygen exited with code $LASTEXITCODE."
    }
}

function Test-GitHubSshKeyUploaded {
    if (-not (Test-GitHubCliAuthenticated) -or -not (Test-WindowsSshKey)) {
        return $false
    }

    $publicKey = (Get-Content -LiteralPath "$(Get-WindowsSshKeyPath).pub" -Raw).Trim()
    $result = Invoke-NativeCommand -FilePath 'gh.exe' -ArgumentList @('ssh-key', 'list', '--json', 'key') -AllowFailure -Quiet
    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Text)) {
        return $false
    }

    try {
        $keys = $result.Text | ConvertFrom-Json
        return @($keys | Where-Object { $_.key -eq $publicKey }).Count -gt 0
    }
    catch {
        return $false
    }
}

function Add-GitHubSshKey {
    $publicKeyPath = "$(Get-WindowsSshKeyPath).pub"
    $title = "{0}-{1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd')
    Invoke-NativeCommand -FilePath 'gh.exe' -ArgumentList @(
        'ssh-key', 'add', $publicKeyPath, '--title', $title, '--type', 'authentication'
    ) | Out-Null
}

function Get-GitTasks {
    return @(
        [pscustomobject]@{
            Id = 'git.windows-config'; Name = 'Configure Git for Windows'; Category = 'Git and GitHub'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $false; Dependencies = @('windows.git', 'windows.vscode')
            Detect = { param($Context) Test-WindowsGitConfiguration -Context $Context }
            Apply = { param($Context) Set-WindowsGitConfiguration -Context $Context }
            Verify = { param($Context) Test-WindowsGitConfiguration -Context $Context }
        }
        [pscustomobject]@{
            Id = 'git.windows-gcm'; Name = 'Configure Git Credential Manager'; Category = 'Git and GitHub'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $false; Dependencies = @('windows.git')
            Detect = { param($Context) Test-GitCredentialManagerConfigured }
            Apply = { param($Context) Set-GitCredentialManager }
            Verify = { param($Context) Test-GitCredentialManagerConfigured }
        }
        [pscustomobject]@{
            Id = 'github.authenticate'; Name = 'Authenticate GitHub CLI'; Category = 'Git and GitHub'; Default = $false
            Profiles = @(); RequiresAdmin = $false; Dependencies = @('windows.github-cli')
            Detect = { param($Context) Test-GitHubCliAuthenticated }
            Apply = { param($Context) Connect-GitHubCli }
            Verify = { param($Context) Test-GitHubCliAuthenticated }
        }
        [pscustomobject]@{
            Id = 'ssh.windows-key'; Name = 'Generate a Windows SSH key'; Category = 'Git and GitHub'; Default = $false
            Profiles = @(); RequiresAdmin = $false; Dependencies = @()
            Detect = { param($Context) Test-WindowsSshKey }
            Apply = { param($Context) New-WindowsSshKey -Context $Context }
            Verify = { param($Context) Test-WindowsSshKey }
        }
        [pscustomobject]@{
            Id = 'ssh.github-upload'; Name = 'Upload the Windows SSH key to GitHub'; Category = 'Git and GitHub'; Default = $false
            Profiles = @(); RequiresAdmin = $false; Dependencies = @('windows.github-cli', 'github.authenticate', 'ssh.windows-key')
            Detect = { param($Context) Test-GitHubSshKeyUploaded }
            Apply = { param($Context) Add-GitHubSshKey }
            Verify = { param($Context) Test-GitHubSshKeyUploaded }
        }
    )
}
