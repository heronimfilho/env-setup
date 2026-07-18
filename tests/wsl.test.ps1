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

$wslGitTask = $tasks | Where-Object { $_.Id -eq 'git.wsl-config' } | Select-Object -First 1
if ($wslGitTask.Dependencies -notcontains 'windows.vscode') {
    throw 'WSL Git configuration must depend on Visual Studio Code.'
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
    'nvm version-remote --lts',
    'current_version',
    'node --version'
)) {
    if (-not $nodeValidation.Contains($fragment)) {
        throw "Node validation is missing: $fragment"
    }
}

$packageValidation = Get-WslBasePackageValidationCommand
foreach ($package in Get-WslBasePackageNames) {
    if (-not $packageValidation.Contains($package)) {
        throw "WSL package validation is missing: $package"
    }
}
foreach ($directory in @('$HOME/projects', '$HOME/bin')) {
    if (-not $packageValidation.Contains($directory)) {
        throw "WSL directory validation is missing: $directory"
    }
}

$quotedHelper = Convert-ToPosixSingleQuotedString -Value '/mnt/c/Program Files (x86)/Git/mingw64/bin/git-credential-manager.exe'
if ($quotedHelper -ne "'/mnt/c/Program Files (x86)/Git/mingw64/bin/git-credential-manager.exe'") {
    throw "The WSL GCM helper path was not quoted safely: $quotedHelper"
}

Write-Host 'WSL task tests passed.'
