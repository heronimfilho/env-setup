#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Runtime.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Diagnostics.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Update.ps1')

$manifest = [pscustomobject]@{
    version = '1.2.3'
    commit = '0123456789abcdef0123456789abcdef01234567'
    archiveSha256 = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
}
Assert-EnvSetupReleaseManifest -Manifest $manifest
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

$invalid = $false
try { Assert-EnvSetupReleaseManifest -Manifest ([pscustomobject]@{ version = 'bad'; commit = 'x'; archiveSha256 = 'y' }) }
catch { $invalid = $true }
if (-not $invalid) { throw 'An invalid release manifest was accepted.' }

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

    Update-EnvSetupGitClone -ProjectRoot $tempRoot -ExpectedVersion '1.2.3'
    if (@($script:GitCalls | Where-Object { $_ -match 'fetch --prune origin main' }).Count -ne 1) { throw 'Git clone update did not fetch origin/main.' }
    if (@($script:GitCalls | Where-Object { $_ -match 'merge --ff-only origin/main' }).Count -ne 1) { throw 'Git clone update did not use a fast-forward merge.' }

    $script:MockGitStatus = ' M setup.ps1'
    $dirtyRejected = $false
    try { Update-EnvSetupGitClone -ProjectRoot $tempRoot -ExpectedVersion '1.2.3' }
    catch { $dirtyRejected = $_.Exception.Message -match 'local changes' }
    if (-not $dirtyRejected) { throw 'Git clone update accepted a dirty working tree.' }

    $script:MockGitStatus = ''
    $script:MockGitBranch = 'feature/test'
    $branchRejected = $false
    try { Update-EnvSetupGitClone -ProjectRoot $tempRoot -ExpectedVersion '1.2.3' }
    catch { $branchRejected = $_.Exception.Message -match 'requires the main branch' }
    if (-not $branchRejected) { throw 'Git clone update accepted a non-main branch.' }
}
finally { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }

$bootstrap = Get-Content -LiteralPath (Join-Path $projectRoot 'bootstrap.ps1') -Raw
foreach ($required in @("Join-Path `$Destination '.git'", 'custom-profiles', "Name -ne 'custom.example.json'", '[switch]$Quiet', 'Write-BootstrapMessage')) {
    if (-not $bootstrap.Contains($required)) { throw "bootstrap.ps1 is missing update protection: $required" }
}

Write-Host 'Update tests passed.'
