#requires -version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$Commit,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ArchiveSha256,

    [string]$Destination = (Join-Path $HOME 'env-setup')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath $Destination) {
    throw "The destination already exists. Remove it or choose another destination: $Destination"
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-{0}" -f [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $tempRoot 'env-setup.zip'
$extractPath = Join-Path $tempRoot 'extracted'
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
    Move-Item -LiteralPath $source.FullName -Destination $Destination
    Write-Host "env-setup was extracted to: $Destination" -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

& (Join-Path $Destination 'setup.ps1')
