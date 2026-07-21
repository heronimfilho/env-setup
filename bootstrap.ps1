#requires -version 5.1

[CmdletBinding()]
param(
    [ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [string]$Destination = (Join-Path $HOME 'env-setup'),
    [string]$Repository = 'heronimfilho/env-setup',
    [switch]$UpdateExisting,
    [switch]$SkipRun,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-BootstrapMessage {
    param([Parameter(Mandatory = $true)][string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
    if (-not $Quiet) { Write-Host $Message -ForegroundColor $Color }
}

function Get-ReleaseAsset {
    param([Parameter(Mandatory = $true)]$Release, [Parameter(Mandatory = $true)][string]$Name)
    $asset = @($Release.assets | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
    if ($null -eq $asset) { throw "GitHub Release asset not found: $Name" }
    return $asset
}

function Get-CurrentWindowsBuild {
    try {
        return [int](Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop)
    }
    catch {
        return [Environment]::OSVersion.Version.Build
    }
}

function Assert-ReleaseMetadata {
    param([Parameter(Mandatory = $true)]$Metadata, [Parameter(Mandatory = $true)][string]$ExpectedVersion)
    foreach ($property in @('version', 'minimumWindowsBuild', 'archiveName', 'archiveSha256')) {
        if ($null -eq $Metadata.PSObject.Properties[$property] -or [string]::IsNullOrWhiteSpace([string]$Metadata.$property)) {
            throw "Release metadata is missing: $property"
        }
    }
    if ([string]$Metadata.version -ne $ExpectedVersion) { throw "Release metadata version mismatch. Expected $ExpectedVersion but received $($Metadata.version)." }
    if ([string]$Metadata.archiveSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Release metadata contains an invalid archive SHA-256.' }
    if ([int]$Metadata.minimumWindowsBuild -lt 19041) { throw 'Release metadata contains an invalid minimum Windows build.' }
    if ([string]$Metadata.archiveName -notmatch '^env-setup-[0-9A-Za-z.-]+\.zip$') { throw 'Release metadata contains an invalid archive name.' }
}

if ((Test-Path -LiteralPath $Destination) -and -not $UpdateExisting) {
    throw "The destination already exists. Remove it, choose another destination, or use -UpdateExisting: $Destination"
}
if ($UpdateExisting -and (Test-Path -LiteralPath (Join-Path $Destination '.git') -PathType Container)) {
    throw 'The destination is a Git clone. Use setup.ps1 -Update so the clone can be updated to a published release tag.'
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{ 'User-Agent' = 'env-setup-bootstrap'; 'Accept' = 'application/vnd.github+json' }
$releaseUri = if ([string]::IsNullOrWhiteSpace($Version)) {
    "https://api.github.com/repos/$Repository/releases/latest"
}
else {
    "https://api.github.com/repos/$Repository/releases/tags/v$Version"
}

Write-BootstrapMessage -Message 'Resolving the GitHub Release...'
$release = Invoke-RestMethod -Uri $releaseUri -Headers $headers -UseBasicParsing
$releaseVersion = ([string]$release.tag_name).TrimStart('v')
if ([string]::IsNullOrWhiteSpace($releaseVersion)) { throw 'The GitHub Release does not have a valid version tag.' }
if (-not [string]::IsNullOrWhiteSpace($Version) -and $releaseVersion -ne $Version) {
    throw "Resolved release version mismatch. Expected $Version but received $releaseVersion."
}

$metadataAsset = Get-ReleaseAsset -Release $release -Name 'env-setup-release.json'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-{0}" -f [guid]::NewGuid().ToString('N'))
$metadataPath = Join-Path $tempRoot 'env-setup-release.json'
$archivePath = Join-Path $tempRoot 'env-setup.zip'
$extractPath = Join-Path $tempRoot 'extracted'
$backupPath = Join-Path $tempRoot 'backup'
$customProfilesPath = Join-Path $tempRoot 'custom-profiles'

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Invoke-WebRequest -Uri $metadataAsset.browser_download_url -OutFile $metadataPath -Headers $headers -UseBasicParsing
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    Assert-ReleaseMetadata -Metadata $metadata -ExpectedVersion $releaseVersion

    $currentBuild = Get-CurrentWindowsBuild
    if ($currentBuild -lt [int]$metadata.minimumWindowsBuild) {
        throw "env-setup $releaseVersion requires Windows build $($metadata.minimumWindowsBuild) or newer. Current build: $currentBuild."
    }

    $archiveAsset = Get-ReleaseAsset -Release $release -Name ([string]$metadata.archiveName)
    Write-BootstrapMessage -Message "Downloading env-setup $releaseVersion from GitHub Releases..."
    Invoke-WebRequest -Uri $archiveAsset.browser_download_url -OutFile $archivePath -Headers $headers -UseBasicParsing

    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = ([string]$metadata.archiveSha256).ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Release archive checksum validation failed. Expected $expectedHash but received $actualHash."
    }
    Write-BootstrapMessage -Message 'Release archive checksum validated.' -Color Green

    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
    $source = Get-ChildItem -LiteralPath $extractPath -Directory | Select-Object -First 1
    if ($null -eq $source -or -not (Test-Path -LiteralPath (Join-Path $source.FullName 'setup.ps1'))) {
        throw 'The downloaded release archive does not contain setup.ps1.'
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    if (-not (Test-Path -LiteralPath $Destination)) {
        Move-Item -LiteralPath $source.FullName -Destination $Destination
        Write-BootstrapMessage -Message "env-setup $releaseVersion was extracted to: $Destination" -Color Green
    }
    else {
        Write-BootstrapMessage -Message "Updating the existing installation to env-setup $releaseVersion..."
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        Get-ChildItem -LiteralPath $Destination -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $backupPath -Recurse -Force
        }

        $existingProfiles = Join-Path $Destination 'profiles'
        if (Test-Path -LiteralPath $existingProfiles -PathType Container) {
            Get-ChildItem -LiteralPath $existingProfiles -Filter '*.json' -File -Recurse |
                Where-Object { $_.Name -ne 'custom.example.json' } |
                ForEach-Object {
                    $relativePath = $_.FullName.Substring($existingProfiles.Length).TrimStart('\')
                    $profileDestination = Join-Path $customProfilesPath $relativePath
                    New-Item -ItemType Directory -Path (Split-Path -Parent $profileDestination) -Force | Out-Null
                    Copy-Item -LiteralPath $_.FullName -Destination $profileDestination -Force
                }
        }

        try {
            Get-ChildItem -LiteralPath $Destination -Force | Remove-Item -Recurse -Force
            Get-ChildItem -LiteralPath $source.FullName -Force | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
            }
            if (Test-Path -LiteralPath $customProfilesPath -PathType Container) {
                Get-ChildItem -LiteralPath $customProfilesPath -File -Recurse | ForEach-Object {
                    $relativePath = $_.FullName.Substring($customProfilesPath.Length).TrimStart('\')
                    $profileDestination = Join-Path (Join-Path $Destination 'profiles') $relativePath
                    New-Item -ItemType Directory -Path (Split-Path -Parent $profileDestination) -Force | Out-Null
                    Copy-Item -LiteralPath $_.FullName -Destination $profileDestination -Force
                }
            }
        }
        catch {
            Get-ChildItem -LiteralPath $Destination -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath $backupPath -Force | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
            }
            throw
        }
        Write-BootstrapMessage -Message 'Existing installation updated successfully.' -Color Green
    }

    $installedVersionPath = Join-Path $Destination 'VERSION'
    $installedVersion = if (Test-Path -LiteralPath $installedVersionPath -PathType Leaf) { (Get-Content -LiteralPath $installedVersionPath -Raw).Trim() } else { '' }
    if ($installedVersion -ne $releaseVersion) {
        throw "Installed version verification failed. Expected $releaseVersion but found '$installedVersion'."
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $SkipRun) {
    & (Join-Path $Destination 'setup.ps1')
}
