#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Runtime.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Diagnostics.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Update.ps1')

$metadata = [pscustomobject]@{
    version = '1.2.3'
    minimumWindowsBuild = 19041
    archiveName = 'env-setup-1.2.3.zip'
    archiveSha256 = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
}
Assert-EnvSetupReleaseMetadata -Metadata $metadata

foreach ($comparison in @(
    @{ Left = '1.2.3'; Right = '1.2.2'; Expected = 1 },
    @{ Left = '1.2.3'; Right = '1.2.3'; Expected = 0 },
    @{ Left = '1.2.2'; Right = '1.2.3'; Expected = -1 },
    @{ Left = '1.2.3-beta'; Right = '1.2.3'; Expected = -1 },
    @{ Left = '1.2.3'; Right = '1.2.3-beta'; Expected = 1 },
    @{ Left = '1.2.3-beta.2'; Right = '1.2.3-beta.10'; Expected = -1 },
    @{ Left = '1.2.3-alpha'; Right = '1.2.3-beta'; Expected = -1 },
    @{ Left = '1.2.3+build.1'; Right = '1.2.3+build.2'; Expected = 0 }
)) {
    $actual = Compare-SemanticVersion -Left $comparison.Left -Right $comparison.Right
    if ([Math]::Sign($actual) -ne $comparison.Expected) {
        throw "Semantic version comparison failed: $($comparison.Left) vs $($comparison.Right), received $actual."
    }
}

foreach ($invalidMetadata in @(
    [pscustomobject]@{ version = 'bad'; minimumWindowsBuild = 19041; archiveName = 'env-setup-bad.zip'; archiveSha256 = ('0' * 64) },
    [pscustomobject]@{ version = '1.2.3'; minimumWindowsBuild = 10000; archiveName = 'env-setup-1.2.3.zip'; archiveSha256 = ('0' * 64) },
    [pscustomobject]@{ version = '1.2.3'; minimumWindowsBuild = 19041; archiveName = 'unexpected.zip'; archiveSha256 = ('0' * 64) },
    [pscustomobject]@{ version = '1.2.3'; minimumWindowsBuild = 19041; archiveName = 'env-setup-1.2.3.zip'; archiveSha256 = 'bad' }
)) {
    $invalidRejected = $false
    try { Assert-EnvSetupReleaseMetadata -Metadata $invalidMetadata }
    catch { $invalidRejected = $true }
    if (-not $invalidRejected) { throw 'Invalid release metadata was accepted.' }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-update-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $tempRoot 'VERSION') -Value '1.2.3'
    $script:MockGitStatus = ''
    $script:MockGitBranch = 'main'
    $script:GitCalls = New-Object System.Collections.Generic.List[string]

    function Test-CommandAvailable {
        param([string]$Name)
        return $Name -in @('git.exe', 'git')
    }
    function Invoke-NativeCommand {
        param([string]$FilePath, [string[]]$ArgumentList, [switch]$AllowFailure, [switch]$Quiet)
        $script:GitCalls.Add(($ArgumentList -join ' '))
        $text = ''
        if ($ArgumentList -contains '--porcelain') { $text = $script:MockGitStatus }
        elseif ($ArgumentList -contains '--show-current') { $text = $script:MockGitBranch }
        return [pscustomobject]@{ ExitCode = 0; Output = @($text); Text = $text }
    }

    Update-EnvSetupGitClone -ProjectRoot $tempRoot -ExpectedVersion '1.2.3' -ExpectedTag 'v1.2.3'
    if (@($script:GitCalls | Where-Object { $_ -match 'fetch --prune --tags origin' }).Count -ne 1) { throw 'Git clone update did not fetch release tags.' }
    if (@($script:GitCalls | Where-Object { $_ -match 'merge --ff-only refs/tags/v1\.2\.3' }).Count -ne 1) { throw 'Git clone update did not fast-forward to the release tag.' }

    $script:MockGitStatus = ' M setup.ps1'
    $dirtyRejected = $false
    try { Update-EnvSetupGitClone -ProjectRoot $tempRoot -ExpectedVersion '1.2.3' -ExpectedTag 'v1.2.3' }
    catch { $dirtyRejected = $_.Exception.Message -match 'local changes' }
    if (-not $dirtyRejected) { throw 'Git clone update accepted a dirty working tree.' }

    $script:MockGitStatus = ''
    $script:MockGitBranch = 'feature/test'
    $branchRejected = $false
    try { Update-EnvSetupGitClone -ProjectRoot $tempRoot -ExpectedVersion '1.2.3' -ExpectedTag 'v1.2.3' }
    catch { $branchRejected = $_.Exception.Message -match 'requires the main branch' }
    if (-not $branchRejected) { throw 'Git clone update accepted a non-main branch.' }
}
finally { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }

$bootstrap = Get-Content -LiteralPath (Join-Path $projectRoot 'bootstrap.ps1') -Raw
foreach ($required in @(
    'releases/latest',
    'releases/tags/v$Version',
    'env-setup-release.json',
    'archiveSha256',
    'minimumWindowsBuild',
    'Get-FileHash',
    "Join-Path `$Destination '.git'",
    'custom-profiles',
    "Name -ne 'custom.example.json'",
    '[switch]$Quiet',
    'Installed version verification failed'
)) {
    if (-not $bootstrap.Contains($required)) { throw "bootstrap.ps1 is missing release update protection: $required" }
}
foreach ($forbidden in @('codeload.github.com', 'ArchiveSha256', '[string]$Commit')) {
    if ($bootstrap.Contains($forbidden)) { throw "bootstrap.ps1 still contains snapshot installation behavior: $forbidden" }
}

$updater = Get-Content -LiteralPath (Join-Path $projectRoot 'src/EnvSetup.Update.ps1') -Raw
foreach ($required in @('Get-EnvSetupCurrentWindowsBuild', 'minimumWindowsBuild', 'Release update verification failed', 'refs/tags/$ExpectedTag')) {
    if (-not $updater.Contains($required)) { throw "Updater is missing release validation: $required" }
}

Write-Host 'Update tests passed.'
