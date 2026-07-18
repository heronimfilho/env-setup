#requires -version 5.1

[CmdletBinding()]
param(
    [string]$Branch = 'main',
    [string]$Destination = (Join-Path $HOME 'env-setup')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath (Join-Path $Destination 'setup.ps1') -PathType Leaf) {
    Write-Host "Using the existing env-setup directory: $Destination" -ForegroundColor Cyan
    & (Join-Path $Destination 'setup.ps1')
    return
}

if (Test-Path -LiteralPath $Destination) {
    throw "The destination already exists and is not an env-setup directory: $Destination"
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-{0}" -f [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $tempRoot 'env-setup.zip'
$extractPath = Join-Path $tempRoot 'extracted'
$archiveUrl = "https://codeload.github.com/heronimfilho/env-setup/zip/refs/heads/$Branch"

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Write-Host "Downloading env-setup from branch '$Branch'..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath -UseBasicParsing
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
