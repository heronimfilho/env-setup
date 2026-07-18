#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.WSL.ps1')

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

$nodeTask = $tasks | Where-Object { $_.Id -eq 'wsl.node' } | Select-Object -First 1
if (-not $nodeTask.Default) {
    throw 'The NVM and Node.js LTS task must be selected by default.'
}

Write-Host 'WSL task tests passed.'
