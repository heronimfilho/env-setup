#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot

$setup = Get-Content -LiteralPath (Join-Path $projectRoot 'setup.ps1') -Raw
$windowsSettingsIndex = $setup.IndexOf('src/EnvSetup.WindowsSettings.ps1')
$progressIndex = $setup.IndexOf('src/EnvSetup.Progress.ps1')
if ($windowsSettingsIndex -lt 0 -or $progressIndex -lt 0 -or $progressIndex -le $windowsSettingsIndex) {
    throw 'setup.ps1 must load the progress-aware task runner explicitly after all feature modules.'
}

$taskFactories = Get-Content -LiteralPath (Join-Path $projectRoot 'src/EnvSetup.TaskFactories.ps1') -Raw
if ($taskFactories.Contains('EnvSetup.Progress.ps1')) {
    throw 'Task factories must not load the progress runner implicitly.'
}

$installWsl = Get-Content -LiteralPath (Join-Path $projectRoot 'install-wsl.ps1') -Raw
foreach ($required in @('setup.ps1', 'wsl.install')) {
    if (-not $installWsl.Contains($required)) {
        throw "install-wsl.ps1 is missing delegation content: $required"
    }
}
if ($installWsl -match 'wsl\.exe\s+--install') {
    throw 'install-wsl.ps1 still performs a direct WSL installation.'
}

$configureZsh = Get-Content -LiteralPath (Join-Path $projectRoot 'configure-zsh.ps1') -Raw
foreach ($required in @('setup.ps1', 'wsl.zsh')) {
    if (-not $configureZsh.Contains($required)) {
        throw "configure-zsh.ps1 is missing delegation content: $required"
    }
}
if ($configureZsh -match 'wsl\.exe\s+--distribution') {
    throw 'configure-zsh.ps1 still performs direct WSL configuration.'
}

$bootstrap = Get-Content -LiteralPath (Join-Path $projectRoot 'bootstrap.ps1') -Raw
foreach ($required in @('Commit', 'ArchiveSha256', 'Get-FileHash', 'codeload.github.com')) {
    if (-not $bootstrap.Contains($required)) {
        throw "bootstrap.ps1 is missing immutable download validation: $required"
    }
}
foreach ($forbidden in @('refs/heads', "Branch = 'main'", 'Branch = "main"')) {
    if ($bootstrap.Contains($forbidden)) {
        throw "bootstrap.ps1 still supports a mutable branch download: $forbidden"
    }
}

$readme = Get-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Raw
foreach ($required in @('799fb06ac409c31c8d81b8f566fcc2ff6fc63664', 'e1aed4fe4e47204c002687ed557ee0b4d2731208457fd6ee80e815d4c8d24eae')) {
    if (-not $readme.Contains($required)) {
        throw "README.md is missing the pinned bootstrap value: $required"
    }
}
foreach ($forbidden in @('raw.githubusercontent.com/heronimfilho/env-setup/main/bootstrap.ps1', 'irm ', '| iex')) {
    if ($readme.Contains($forbidden)) {
        throw "README.md contains an unsafe bootstrap pattern: $forbidden"
    }
}

Write-Host 'Entrypoint tests passed.'
