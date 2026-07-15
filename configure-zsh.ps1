#requires -version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Distribution = "Ubuntu"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Status {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-Failure {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

function Get-InstalledDistributions {
    $output = & wsl.exe --list --quiet 2>$null

    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    return @(
        $output |
            ForEach-Object { ($_ -replace "`0", "").Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-DistributionDefaultUid {
    param([string]$DistributionName)

    $registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"

    if (-not (Test-Path -LiteralPath $registryPath)) {
        return $null
    }

    $distribution = Get-ChildItem -LiteralPath $registryPath |
        ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath } |
        Where-Object { $_.DistributionName -eq $DistributionName } |
        Select-Object -First 1

    if ($null -eq $distribution) {
        return $null
    }

    $defaultUidProperty = $distribution.PSObject.Properties["DefaultUid"]

    if ($null -eq $defaultUidProperty) {
        return $null
    }

    return [uint32]$defaultUidProperty.Value
}

try {
    $installedDistributions = Get-InstalledDistributions

    if ($installedDistributions -notcontains $Distribution) {
        throw "$Distribution is not installed. Run .\install-wsl.ps1 first."
    }

    $defaultUid = Get-DistributionDefaultUid -DistributionName $Distribution

    if ($null -eq $defaultUid -or $defaultUid -eq 0) {
        throw "Launch $Distribution once and finish creating a non-root Linux user."
    }

    $scriptPath = Join-Path $PSScriptRoot "configure-zsh.sh"

    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "configure-zsh.sh was not found next to configure-zsh.ps1."
    }

    $defaultUserId = (& wsl.exe --distribution $Distribution --exec sh -c "id -u" 2>$null | Out-String).Trim()

    if ($LASTEXITCODE -ne 0) {
        throw "Launch $Distribution once and finish creating the Linux user."
    }

    if ($defaultUserId -eq "0") {
        throw "The default Linux user is root. Create or configure a non-root user first."
    }

    $wslScriptPath = (& wsl.exe --distribution $Distribution --exec wslpath -a -u $scriptPath | Out-String).Trim()

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($wslScriptPath)) {
        throw "Could not convert the setup script path for WSL."
    }

    Write-Status "Configuring Zsh in $Distribution..."
    & wsl.exe --distribution $Distribution --exec bash $wslScriptPath

    if ($LASTEXITCODE -ne 0) {
        throw "Zsh configuration failed with exit code $LASTEXITCODE."
    }

    Write-Success "Zsh configuration completed."
}
catch {
    Write-Failure $_.Exception.Message
    exit 1
}
