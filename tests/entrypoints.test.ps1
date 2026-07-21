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
    if (-not $installWsl.Contains($required)) { throw "install-wsl.ps1 is missing delegation content: $required" }
}
if ($installWsl -match 'wsl\.exe\s+--install') { throw 'install-wsl.ps1 still performs a direct WSL installation.' }

$configureZsh = Get-Content -LiteralPath (Join-Path $projectRoot 'configure-zsh.ps1') -Raw
foreach ($required in @('setup.ps1', 'wsl.zsh')) {
    if (-not $configureZsh.Contains($required)) { throw "configure-zsh.ps1 is missing delegation content: $required" }
}
if ($configureZsh -match 'wsl\.exe\s+--distribution') { throw 'configure-zsh.ps1 still performs direct WSL configuration.' }

$bootstrap = Get-Content -LiteralPath (Join-Path $projectRoot 'bootstrap.ps1') -Raw
foreach ($required in @('releases/latest', 'releases/tags/v$Version', 'env-setup-release.json', 'archiveSha256', 'minimumWindowsBuild', 'Get-FileHash')) {
    if (-not $bootstrap.Contains($required)) { throw "bootstrap.ps1 is missing GitHub Release validation: $required" }
}
foreach ($forbidden in @('codeload.github.com', 'refs/heads', '[string]$Commit', '[string]$ArchiveSha256')) {
    if ($bootstrap.Contains($forbidden)) { throw "bootstrap.ps1 still supports snapshot downloads: $forbidden" }
}

$readme = Get-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Raw
foreach ($required in @(
    'releases/latest/download/env-setup-bootstrap.ps1',
    "& `$bootstrap",
    "-Version '0.4.0'",
    'env-setup-release.json',
    'SHA256SUMS'
)) {
    if (-not $readme.Contains($required)) { throw "README.md is missing release installation content: $required" }
}
foreach ($forbidden in @('raw.githubusercontent.com/heronimfilho/env-setup/', 'codeload.github.com', '$commit =', '$archiveSha256 =', 'irm ', '| iex')) {
    if ($readme.Contains($forbidden)) { throw "README.md contains an obsolete or unsafe installation pattern: $forbidden" }
}

$releaseWorkflow = Get-Content -LiteralPath (Join-Path $projectRoot '.github/workflows/release.yml') -Raw
foreach ($required in @('git archive', 'env-setup-bootstrap.ps1', 'env-setup-release.json', 'SHA256SUMS', 'gh release create')) {
    if (-not $releaseWorkflow.Contains($required)) { throw "Release workflow is missing asset publication: $required" }
}
if ($releaseWorkflow.Contains('release-manifest.json') -or $releaseWorkflow.Contains('codeload.github.com')) {
    throw 'Release workflow still depends on snapshot manifest or codeload archives.'
}

if (Test-Path -LiteralPath (Join-Path $projectRoot 'release-manifest.json')) {
    throw 'The obsolete snapshot release manifest still exists.'
}

Write-Host 'Entrypoint tests passed.'
