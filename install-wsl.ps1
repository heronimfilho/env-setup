#requires -version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Distribution = "Ubuntu",

    [Parameter()]
    [switch]$WebDownload
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

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [int[]]$SuccessExitCodes = @(0, 3010)
    )

    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }

    if ($SuccessExitCodes -notcontains $exitCode) {
        throw "Command failed with exit code ${exitCode}: $FilePath $($Arguments -join ' ')"
    }

    return $exitCode
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

$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Failure "Run PowerShell as Administrator."
    exit 1
}

$build = [int](Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber")

if ($build -lt 19041) {
    Write-Failure "Windows 10 build 19041 or newer is required."
    exit 1
}

try {
    $installedDistributions = Get-InstalledDistributions

    if ($installedDistributions -contains $Distribution) {
        Write-Status "$Distribution is already installed."
        Invoke-NativeCommand -FilePath "wsl.exe" -Arguments @(
            "--set-version",
            $Distribution,
            "2"
        ) | Out-Null

        Write-Success "$Distribution is configured to use WSL 2."
        exit 0
    }

    $arguments = @(
        "--install",
        "--distribution",
        $Distribution,
        "--no-launch"
    )

    if ($WebDownload) {
        $arguments += "--web-download"
    }

    Write-Status "Installing WSL 2 with $Distribution..."
    $exitCode = Invoke-NativeCommand -FilePath "wsl.exe" -Arguments $arguments

    Write-Success "WSL installation command completed."
    Write-Host ""
    Write-Host "Next:" -ForegroundColor Yellow
    Write-Host "1. Restart Windows."
    Write-Host "2. Launch $Distribution and create the Linux user."
    Write-Host "3. Run .\configure-zsh.ps1 -Distribution '$Distribution'."

    if ($exitCode -eq 3010) {
        Write-Host "A restart is required." -ForegroundColor Yellow
    }
}
catch {
    Write-Failure $_.Exception.Message
    exit 1
}
