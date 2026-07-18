#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot

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
foreach ($required in @('6c92936c263ba36c4ebe0ecb810a5897d8c771ce', '2281d35090a9bb9e65f2bc8d70086339f116a9011e4a024c978f6df14058bd99')) {
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
