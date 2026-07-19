Set-StrictMode -Version Latest

function Assert-EnvSetupReleaseManifest {
    param([Parameter(Mandatory = $true)]$Manifest)
    foreach ($property in @('version', 'commit', 'archiveSha256')) {
        if ($null -eq $Manifest.PSObject.Properties[$property] -or [string]::IsNullOrWhiteSpace([string]$Manifest.$property)) {
            throw "Release manifest is missing: $property"
        }
    }
    if ([string]$Manifest.version -notmatch '^\d+\.\d+\.\d+([-.][0-9A-Za-z.-]+)?$') { throw 'Release manifest contains an invalid semantic version.' }
    if ([string]$Manifest.commit -notmatch '^[0-9a-fA-F]{40}$') { throw 'Release manifest contains an invalid commit SHA.' }
    if ([string]$Manifest.archiveSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Release manifest contains an invalid archive SHA-256.' }
}

function Get-EnvSetupReleaseManifest {
    param([string]$Uri = 'https://raw.githubusercontent.com/heronimfilho/env-setup/main/release-manifest.json')
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing
    $manifest = $response.Content | ConvertFrom-Json
    Assert-EnvSetupReleaseManifest -Manifest $manifest
    return $manifest
}

function Compare-SemanticVersion {
    param([Parameter(Mandatory = $true)][string]$Left, [Parameter(Mandatory = $true)][string]$Right)
    $leftCore = ($Left -split '[-+]')[0]
    $rightCore = ($Right -split '[-+]')[0]
    return ([version]$leftCore).CompareTo([version]$rightCore)
}

function Invoke-EnvSetupUpdate {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Force,
        [string]$ManifestUri = 'https://raw.githubusercontent.com/heronimfilho/env-setup/main/release-manifest.json'
    )

    $currentVersion = Get-EnvSetupVersion -ProjectRoot $ProjectRoot
    Write-SetupMessage -Message "Checking for env-setup updates (current version: $currentVersion)..." -Level Info -Event 'update-check'
    $manifest = Get-EnvSetupReleaseManifest -Uri $ManifestUri
    if (-not $Force -and (Compare-SemanticVersion -Left $manifest.version -Right $currentVersion) -le 0) {
        Write-SetupMessage -Message "env-setup $currentVersion is already current." -Level Success -Event 'update-current'
        return [pscustomobject]@{ updated = $false; currentVersion = $currentVersion; latestVersion = $manifest.version }
    }

    $bootstrapPath = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-bootstrap-{0}.ps1" -f $manifest.commit)
    $bootstrapUri = "https://raw.githubusercontent.com/heronimfilho/env-setup/$($manifest.commit)/bootstrap.ps1"
    Write-SetupMessage -Message "Downloading the verified updater for version $($manifest.version)..." -Level Muted -Event 'update-download'
    Invoke-WebRequest -Uri $bootstrapUri -OutFile $bootstrapPath -UseBasicParsing

    & $bootstrapPath -Commit $manifest.commit -ArchiveSha256 $manifest.archiveSha256 -Destination $ProjectRoot -UpdateExisting -SkipRun
    if ($LASTEXITCODE -ne 0) { throw "The updater exited with code $LASTEXITCODE." }
    Write-SetupMessage -Message "env-setup was updated from $currentVersion to $($manifest.version). Run setup.ps1 again to use the new version." -Level Success -Event 'update-complete'
    return [pscustomobject]@{ updated = $true; previousVersion = $currentVersion; latestVersion = $manifest.version; commit = $manifest.commit }
}
