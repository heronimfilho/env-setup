#requires -version 5.1

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Distribution = 'Ubuntu',
    [switch]$Check,
    [switch]$DryRun,
    [switch]$Repair,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$setupPath = Join-Path $PSScriptRoot 'setup.ps1'
if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
    throw 'setup.ps1 was not found next to configure-zsh.ps1.'
}

Write-Host 'This compatibility entry point delegates Zsh configuration to setup.ps1.' -ForegroundColor DarkGray

$arguments = @{
    Include         = @('wsl.zsh')
    WslDistribution = $Distribution
}
if ($Check) { $arguments.Check = $true }
if ($DryRun) { $arguments.DryRun = $true }
if ($Repair) { $arguments.Repair = $true }
if ($NonInteractive) { $arguments.NonInteractive = $true }

& $setupPath @arguments
