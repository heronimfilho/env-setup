#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.WSL.ps1')

if (-not (Test-WslDistributionSupported -Distribution 'Ubuntu-24.04')) {
    throw 'Ubuntu-24.04 should be supported.'
}
if (Test-WslDistributionSupported -Distribution 'openSUSE-Tumbleweed') {
    throw 'Unsupported non-APT distributions must be rejected.'
}

function Test-CommandAvailable {
    param([string]$Name)
    return $true
}

function Invoke-NativeCommand {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [switch]$AllowFailure,
        [switch]$Quiet
    )

    return [pscustomobject]@{
        ExitCode = 0
        Output = @(
            '  NAME                   STATE           VERSION',
            '* Ubuntu                 Running         2',
            '  Debian                 Stopped         1'
        )
        Text = ''
    }
}

if ((Get-WslDistributionVersion -Distribution 'Ubuntu') -ne 2) {
    throw 'WSL 2 distribution parsing failed.'
}
if ((Get-WslDistributionVersion -Distribution 'Debian') -ne 1) {
    throw 'WSL 1 distribution parsing failed.'
}

$tasks = @(Get-WslTasks)
$taskIds = @($tasks | ForEach-Object { $_.Id })
$expected = @(
    'wsl.install',
    'wsl.initialize',
    'wsl.base',
    'git.wsl-config',
    'git.wsl-gcm',
    'wsl.zsh',
    'wsl.node'
)

foreach ($taskId in $expected) {
    if ($taskIds -notcontains $taskId) {
        throw "Missing WSL task: $taskId"
    }
}

$order = Resolve-TaskOrder -Tasks $tasks -SelectedTaskIds @('wsl.node')
$expectedOrder = 'wsl.install,wsl.initialize,wsl.base,wsl.zsh,wsl.node'
if (($order -join ',') -ne $expectedOrder) {
    throw "Unexpected Node.js task order: $($order -join ',')"
}

$installTask = $tasks | Where-Object { $_.Id -eq 'wsl.install' } | Select-Object -First 1
if ($installTask.Detect.ToString() -notmatch 'Test-WslDistributionReady') {
    throw 'The WSL install task must validate WSL 2, not only distribution presence.'
}

$nodeTask = $tasks | Where-Object { $_.Id -eq 'wsl.node' } | Select-Object -First 1
if (-not $nodeTask.Default) {
    throw 'The NVM and Node.js LTS task must be selected by default.'
}

$nodeValidation = Get-WslNodeValidationCommand
foreach ($fragment in @(
    'nvm --version',
    '0.40.4',
    'default -> lts/*',
    "nvm version 'lts/*'",
    'node --version'
)) {
    if (-not $nodeValidation.Contains($fragment)) {
        throw "Node validation is missing: $fragment"
    }
}

Write-Host 'WSL task tests passed.'
