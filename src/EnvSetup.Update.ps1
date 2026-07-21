Set-StrictMode -Version Latest

function ConvertTo-SemanticVersionParts {
    param([Parameter(Mandatory = $true)][string]$Version)
    $match = [regex]::Match($Version, '^(?<core>\d+\.\d+\.\d+)(?:-(?<pre>[0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$')
    if (-not $match.Success) { throw "Invalid semantic version: $Version" }
    return [pscustomobject]@{
        Core = [version]$match.Groups['core'].Value
        Prerelease = [string]$match.Groups['pre'].Value
    }
}

function Compare-SemanticVersion {
    param([Parameter(Mandatory = $true)][string]$Left, [Parameter(Mandatory = $true)][string]$Right)
    $leftParts = ConvertTo-SemanticVersionParts -Version $Left
    $rightParts = ConvertTo-SemanticVersionParts -Version $Right
    $coreComparison = $leftParts.Core.CompareTo($rightParts.Core)
    if ($coreComparison -ne 0) { return $coreComparison }

    $leftPre = $leftParts.Prerelease
    $rightPre = $rightParts.Prerelease
    if ([string]::IsNullOrWhiteSpace($leftPre) -and [string]::IsNullOrWhiteSpace($rightPre)) { return 0 }
    if ([string]::IsNullOrWhiteSpace($leftPre)) { return 1 }
    if ([string]::IsNullOrWhiteSpace($rightPre)) { return -1 }

    $leftIdentifiers = @($leftPre -split '\.')
    $rightIdentifiers = @($rightPre -split '\.')
    $length = [Math]::Max($leftIdentifiers.Count, $rightIdentifiers.Count)
    for ($index = 0; $index -lt $length; $index++) {
        if ($index -ge $leftIdentifiers.Count) { return -1 }
        if ($index -ge $rightIdentifiers.Count) { return 1 }

        $leftIdentifier = $leftIdentifiers[$index]
        $rightIdentifier = $rightIdentifiers[$index]
        $leftNumber = 0L
        $rightNumber = 0L
        $leftNumeric = [long]::TryParse($leftIdentifier, [ref]$leftNumber)
        $rightNumeric = [long]::TryParse($rightIdentifier, [ref]$rightNumber)
        if ($leftNumeric -and $rightNumeric) {
            $comparison = $leftNumber.CompareTo($rightNumber)
        }
        elseif ($leftNumeric) { return -1 }
        elseif ($rightNumeric) { return 1 }
        else { $comparison = [string]::CompareOrdinal($leftIdentifier, $rightIdentifier) }
        if ($comparison -ne 0) { return $comparison }
    }
    return 0
}

function Get-EnvSetupCurrentWindowsBuild {
    try {
        return [int](Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop)
    }
    catch {
        return [Environment]::OSVersion.Version.Build
    }
}

function Assert-EnvSetupReleaseMetadata {
    param([Parameter(Mandatory = $true)]$Metadata)
    foreach ($property in @('version', 'minimumWindowsBuild', 'archiveName', 'archiveSha256')) {
        if ($null -eq $Metadata.PSObject.Properties[$property] -or [string]::IsNullOrWhiteSpace([string]$Metadata.$property)) {
            throw "Release metadata is missing: $property"
        }
    }
    [void](ConvertTo-SemanticVersionParts -Version ([string]$Metadata.version))
    if ([int]$Metadata.minimumWindowsBuild -lt 19041) { throw 'Release metadata contains an invalid minimum Windows build.' }
    if ([string]$Metadata.archiveName -notmatch '^env-setup-[0-9A-Za-z.-]+\.zip$') { throw 'Release metadata contains an invalid archive name.' }
    if ([string]$Metadata.archiveSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Release metadata contains an invalid archive SHA-256.' }
}

function Get-EnvSetupReleaseAsset {
    param([Parameter(Mandatory = $true)]$Release, [Parameter(Mandatory = $true)][string]$Name)
    $asset = @($Release.assets | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
    if ($null -eq $asset) { throw "GitHub Release asset not found: $Name" }
    return $asset
}

function Get-EnvSetupRelease {
    param(
        [string]$Repository = 'heronimfilho/env-setup',
        [string]$Version
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'env-setup-updater'; 'Accept' = 'application/vnd.github+json' }
    $uri = if ([string]::IsNullOrWhiteSpace($Version)) {
        "https://api.github.com/repos/$Repository/releases/latest"
    }
    else {
        "https://api.github.com/repos/$Repository/releases/tags/v$Version"
    }

    $release = Invoke-RestMethod -Uri $uri -Headers $headers -UseBasicParsing
    $resolvedVersion = ([string]$release.tag_name).TrimStart('v')
    [void](ConvertTo-SemanticVersionParts -Version $resolvedVersion)
    if (-not [string]::IsNullOrWhiteSpace($Version) -and $resolvedVersion -ne $Version) {
        throw "Resolved release version mismatch. Expected $Version but received $resolvedVersion."
    }

    $metadataAsset = Get-EnvSetupReleaseAsset -Release $release -Name 'env-setup-release.json'
    $response = Invoke-WebRequest -Uri $metadataAsset.browser_download_url -Headers $headers -UseBasicParsing
    $metadata = $response.Content | ConvertFrom-Json
    Assert-EnvSetupReleaseMetadata -Metadata $metadata
    if ([string]$metadata.version -ne $resolvedVersion) {
        throw "Release metadata version mismatch. Expected $resolvedVersion but received $($metadata.version)."
    }

    $archiveAsset = Get-EnvSetupReleaseAsset -Release $release -Name ([string]$metadata.archiveName)
    return [pscustomobject]@{
        Version = $resolvedVersion
        TagName = [string]$release.tag_name
        Metadata = $metadata
        ArchiveUrl = [string]$archiveAsset.browser_download_url
        ReleaseUrl = [string]$release.html_url
    }
}

function Update-EnvSetupGitClone {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion,
        [Parameter(Mandatory = $true)][string]$ExpectedTag
    )

    if (-not (Test-CommandAvailable -Name 'git.exe') -and -not (Test-CommandAvailable -Name 'git')) {
        throw 'This env-setup installation is a Git clone, but Git is not available for a safe update.'
    }
    $gitCommand = if (Test-CommandAvailable -Name 'git.exe') { 'git.exe' } else { 'git' }
    $status = Invoke-NativeCommand -FilePath $gitCommand -ArgumentList @('-C', $ProjectRoot, 'status', '--porcelain') -Quiet
    if (-not [string]::IsNullOrWhiteSpace($status.Text)) { throw 'The env-setup Git working tree has local changes. Commit or discard them before running -Update.' }
    $branch = (Invoke-NativeCommand -FilePath $gitCommand -ArgumentList @('-C', $ProjectRoot, 'branch', '--show-current') -Quiet).Text.Trim()
    if ($branch -ne 'main') { throw "Self-update for Git clones requires the main branch. Current branch: $branch" }

    Invoke-NativeCommand -FilePath $gitCommand -ArgumentList @('-C', $ProjectRoot, 'fetch', '--prune', '--tags', 'origin') | Out-Null
    Invoke-NativeCommand -FilePath $gitCommand -ArgumentList @('-C', $ProjectRoot, 'merge', '--ff-only', "refs/tags/$ExpectedTag") | Out-Null
    $installedVersion = Get-EnvSetupVersion -ProjectRoot $ProjectRoot
    if ($installedVersion -ne $ExpectedVersion) { throw "Git update verification failed. Expected version $ExpectedVersion but installed version is $installedVersion." }
}

function Invoke-EnvSetupUpdate {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Force,
        [string]$Repository = 'heronimfilho/env-setup'
    )

    $currentVersion = Get-EnvSetupVersion -ProjectRoot $ProjectRoot
    Write-SetupMessage -Message "Checking GitHub Releases for env-setup updates (current version: $currentVersion)..." -Level Info -Event 'update-check'
    $release = Get-EnvSetupRelease -Repository $Repository
    if (-not $Force -and (Compare-SemanticVersion -Left $release.Version -Right $currentVersion) -le 0) {
        Write-SetupMessage -Message "env-setup $currentVersion is already current." -Level Success -Event 'update-current'
        return [pscustomobject]@{ updated = $false; currentVersion = $currentVersion; latestVersion = $release.Version; releaseUrl = $release.ReleaseUrl }
    }

    $currentBuild = Get-EnvSetupCurrentWindowsBuild
    if ($currentBuild -lt [int]$release.Metadata.minimumWindowsBuild) {
        throw "env-setup $($release.Version) requires Windows build $($release.Metadata.minimumWindowsBuild) or newer. Current build: $currentBuild."
    }

    if (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git') -PathType Container) {
        Write-SetupMessage -Message "Updating the clean main branch to release $($release.TagName)..." -Level Muted -Event 'update-git'
        Update-EnvSetupGitClone -ProjectRoot $ProjectRoot -ExpectedVersion $release.Version -ExpectedTag $release.TagName
    }
    else {
        $bootstrapPath = Join-Path $ProjectRoot 'bootstrap.ps1'
        if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) { throw 'bootstrap.ps1 was not found in the current installation.' }
        Write-SetupMessage -Message "Installing published release $($release.Version)..." -Level Muted -Event 'update-release'
        & $bootstrapPath -Version $release.Version -Repository $Repository -Destination $ProjectRoot -UpdateExisting -SkipRun -Quiet
        $installedVersion = Get-EnvSetupVersion -ProjectRoot $ProjectRoot
        if ($installedVersion -ne $release.Version) {
            throw "Release update verification failed. Expected version $($release.Version) but installed version is $installedVersion."
        }
    }

    Write-SetupMessage -Message "env-setup was updated from $currentVersion to $($release.Version). Run setup.ps1 again to use the new version." -Level Success -Event 'update-complete'
    return [pscustomobject]@{ updated = $true; previousVersion = $currentVersion; latestVersion = $release.Version; tag = $release.TagName; releaseUrl = $release.ReleaseUrl }
}
