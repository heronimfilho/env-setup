#requires -version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$Commit,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ArchiveSha256,

    [string]$Destination = (Join-Path $HOME 'env-setup'),
    [switch]$UpdateExisting,
    [switch]$SkipRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ((Test-Path -LiteralPath $Destination) -and -not $UpdateExisting) {
    throw "The destination already exists. Remove it, choose another destination, or use -UpdateExisting: $Destination"
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-{0}" -f [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $tempRoot 'env-setup.zip'
$extractPath = Join-Path $tempRoot 'extracted'
$backupPath = Join-Path $tempRoot 'backup'
$archiveUrl = "https://codeload.github.com/heronimfilho/env-setup/zip/$Commit"

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Write-Host "Downloading env-setup commit $Commit..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath -UseBasicParsing

    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = $ArchiveSha256.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Archive checksum validation failed. Expected $expectedHash but received $actualHash."
    }
    Write-Host 'Archive checksum validated.' -ForegroundColor Green

    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
    $source = Get-ChildItem -LiteralPath $extractPath -Directory | Select-Object -First 1
    if ($null -eq $source -or -not (Test-Path -LiteralPath (Join-Path $source.FullName 'setup.ps1'))) {
        throw 'The downloaded archive does not contain setup.ps1.'
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    if (-not (Test-Path -LiteralPath $Destination)) {
        Move-Item -LiteralPath $source.FullName -Destination $Destination
        Write-Host "env-setup was extracted to: $Destination" -ForegroundColor Green
    }
    else {
        Write-Host "Updating the existing env-setup installation at: $Destination" -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        Get-ChildItem -LiteralPath $Destination -Force | Where-Object { $_.Name -ne '.git' } | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $backupPath -Recurse -Force
        }

        try {
            Get-ChildItem -LiteralPath $Destination -Force | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force
            Get-ChildItem -LiteralPath $source.FullName -Force | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
            }
        }
        catch {
            Get-ChildItem -LiteralPath $Destination -Force | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath $backupPath -Force | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
            }
            throw
        }
        Write-Host 'Existing installation updated successfully.' -ForegroundColor Green
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $SkipRun) {
    & (Join-Path $Destination 'setup.ps1')
}
