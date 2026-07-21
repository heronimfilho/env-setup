#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$setupPath = Join-Path $projectRoot 'setup.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-integration-{0}" -f [guid]::NewGuid().ToString('N'))
$previousLocalAppData = $env:LOCALAPPDATA
$previousPath = $env:PATH
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $mockBin = Join-Path $tempRoot 'bin'
    New-Item -ItemType Directory -Path $mockBin -Force | Out-Null
    $mockWinget = Join-Path $mockBin 'winget.exe'
    Add-Type -TypeDefinition @'
using System;
public static class WingetStub {
    public static int Main(string[] args) {
        return 0;
    }
}
'@ -OutputAssembly $mockWinget -OutputType ConsoleApplication
    $env:PATH = "$mockBin;$previousPath"

    foreach ($mode in @('Check', 'DryRun')) {
        $dataPath = Join-Path $tempRoot $mode.ToLowerInvariant()
        $env:LOCALAPPDATA = $dataPath
        if ($mode -eq 'Check') {
            & $setupPath -Include windows.powershell,windows.show-extensions -Check -NonInteractive
        }
        else {
            & $setupPath -Include windows.powershell,windows.show-extensions -DryRun -NonInteractive
        }
        if (Test-Path -LiteralPath (Join-Path $dataPath 'env-setup')) { throw "$mode mode created env-setup storage." }
    }

    $configPath = Join-Path $tempRoot 'minimal.json'
    [System.IO.File]::WriteAllText($configPath, '{"selectedTasks":["windows.show-extensions"]}', [System.Text.UTF8Encoding]::new($false))
    $configDataPath = Join-Path $tempRoot 'config'
    $env:LOCALAPPDATA = $configDataPath
    & $setupPath -Config $configPath -Check -NonInteractive
    if (Test-Path -LiteralPath (Join-Path $configDataPath 'env-setup')) { throw 'A minimal configuration check created env-setup storage.' }

    $jsonDataPath = Join-Path $tempRoot 'json'
    $env:LOCALAPPDATA = $jsonDataPath
    $jsonLines = @(& $setupPath -Include windows.powershell,windows.show-extensions -Check -NonInteractive -OutputFormat Json -NoColor 6>&1 | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($jsonLines.Count -lt 4) { throw "The JSON setup run emitted too few events: $($jsonLines.Count)" }
    $jsonEvents = @(
        foreach ($line in $jsonLines) {
            try { $line | ConvertFrom-Json }
            catch { throw "The setup emitted a non-JSON line: $line" }
        }
    )
    if (@($jsonEvents | Where-Object event -eq 'setup-summary').Count -ne 1) { throw 'The JSON setup run did not emit exactly one setup summary.' }
    if (Test-Path -LiteralPath (Join-Path $jsonDataPath 'env-setup')) { throw 'A JSON check created env-setup storage.' }

    $excludeFailed = $false
    $env:LOCALAPPDATA = Join-Path $tempRoot 'exclude'
    try {
        & $setupPath -Include git.windows-config -Exclude windows.vscode -Check -NonInteractive `
            -GitName 'Test Developer' -GitEmail 'developer@example.com'
    }
    catch {
        if ($_.Exception.Message -match 'Cannot exclude required task dependencies') { $excludeFailed = $true }
        else { throw }
    }
    if (-not $excludeFailed) { throw 'setup.ps1 accepted an excluded transitive dependency.' }

    $currentHostPath = (Get-Process -Id $PID).Path
    $env:PATH = Split-Path -Parent $currentHostPath
    $env:LOCALAPPDATA = Join-Path $tempRoot 'doctor'
    $doctorOutput = Join-Path $tempRoot 'doctor-output.log'
    & $currentHostPath -NoProfile -File $setupPath -Doctor -DoctorSkipNetwork -NoColor *> $doctorOutput
    $doctorExitCode = $LASTEXITCODE
    if ($doctorExitCode -ne 1) {
        $details = if (Test-Path -LiteralPath $doctorOutput) { Get-Content -LiteralPath $doctorOutput -Raw } else { '' }
        throw "Doctor failures did not produce process exit code 1. Received $doctorExitCode.`n$details"
    }

    Write-Host 'Setup integration tests passed.'
}
finally {
    $env:LOCALAPPDATA = $previousLocalAppData
    $env:PATH = $previousPath
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
