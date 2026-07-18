#requires -version 5.1

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Distribution = 'Ubuntu',
    [switch]$WebDownload,
    [switch]$Check,
    [switch]$DryRun,
    [switch]$Repair,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$setupPath = Join-Path $PSScriptRoot 'setup.ps1'
if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
    throw 'setup.ps1 was not found next to install-wsl.ps1.'
}

Write-Host 'This compatibility entry point delegates WSL installation to setup.ps1.' -ForegroundColor DarkGray

$arguments = @{
    Include         = @('wsl.install')
    WslDistribution = $Distribution
}
if ($WebDownload) { $arguments.WslWebDownload = $true }
if ($Check) { $arguments.Check = $true }
if ($DryRun) { $arguments.DryRun = $true }
if ($Repair) { $arguments.Repair = $true }
if ($NonInteractive) { $arguments.NonInteractive = $true }

& $setupPath @arguments
