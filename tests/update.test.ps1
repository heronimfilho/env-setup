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
if ((Compare-SemanticVersion -Left '1.2.3' -Right '1.2.2') -le 0) { throw 'Semantic version comparison failed for a newer version.' }
if ((Compare-SemanticVersion -Left '1.2.3' -Right '1.2.3') -ne 0) { throw 'Semantic version comparison failed for equal versions.' }
if ((Compare-SemanticVersion -Left '1.2.2' -Right '1.2.3') -ge 0) { throw 'Semantic version comparison failed for an older version.' }

$invalid = $false
try { Assert-EnvSetupReleaseManifest -Manifest ([pscustomobject]@{ version = 'bad'; commit = 'x'; archiveSha256 = 'y' }) }
catch { $invalid = $true }
if (-not $invalid) { throw 'An invalid release manifest was accepted.' }

Write-Host 'Update tests passed.'
