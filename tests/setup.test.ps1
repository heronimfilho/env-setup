#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$setupPath = Join-Path $projectRoot 'setup.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-integration-{0}" -f [guid]::NewGuid().ToString('N'))
$previousLocalAppData = $env:LOCALAPPDATA
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

function global:winget.exe {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $global:LASTEXITCODE = 0
    Write-Output '7zip.7zip'
}

try {
    foreach ($mode in @('Check', 'DryRun')) {
        $dataPath = Join-Path $tempRoot $mode.ToLowerInvariant()
        $env:LOCALAPPDATA = $dataPath
        if ($mode -eq 'Check') {
            & $setupPath -Include windows.7zip -Check -NonInteractive
        }
        else {
            & $setupPath -Include windows.7zip -DryRun -NonInteractive
        }

        if (Test-Path -LiteralPath (Join-Path $dataPath 'env-setup')) {
            throw "$mode mode created env-setup storage."
        }
    }

    $configPath = Join-Path $tempRoot 'minimal.json'
    [System.IO.File]::WriteAllText($configPath, '{"selectedTasks":["windows.7zip"]}', [System.Text.UTF8Encoding]::new($false))
    $configDataPath = Join-Path $tempRoot 'config'
    $env:LOCALAPPDATA = $configDataPath
    & $setupPath -Config $configPath -Check -NonInteractive
    if (Test-Path -LiteralPath (Join-Path $configDataPath 'env-setup')) {
        throw 'A minimal configuration check created env-setup storage.'
    }

    $excludeFailed = $false
    $env:LOCALAPPDATA = Join-Path $tempRoot 'exclude'
    try {
        & $setupPath -Include git.windows-config -Exclude windows.vscode -Check -NonInteractive `
            -GitName 'Test Developer' -GitEmail 'developer@example.com'
    }
    catch {
        if ($_.Exception.Message -match 'Cannot exclude required task dependencies') {
            $excludeFailed = $true
        }
        else {
            throw
        }
    }
    if (-not $excludeFailed) {
        throw 'setup.ps1 accepted an excluded transitive dependency.'
    }

    Write-Host 'Setup integration tests passed.'
}
finally {
    Remove-Item Function:\global:winget.exe -ErrorAction SilentlyContinue
    $env:LOCALAPPDATA = $previousLocalAppData
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
