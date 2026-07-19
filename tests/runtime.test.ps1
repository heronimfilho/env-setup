#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Runtime.ps1')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-runtime-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $logPath = Join-Path $tempRoot 'runtime.log'
    Initialize-SetupOutput -NoColor -OutputFormat Text -LogPath $logPath -HeartbeatSeconds 2
    $messages = @(& {
        Invoke-NativeCommand -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 3; Write-Output done') -Quiet
    } 6>&1 | ForEach-Object { [string]$_ })
    if (($messages -join "`n") -notmatch 'Still working') { throw 'A long-running native process did not emit a heartbeat.' }
    if (-not (Test-Path -LiteralPath $logPath)) { throw 'Runtime messages were not written to the execution log.' }

    $timedOut = $false
    try {
        Invoke-NativeCommand -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 3') -Quiet -TimeoutSeconds 1 | Out-Null
    }
    catch { $timedOut = $_.Exception.Message -match 'timed out' }
    if (-not $timedOut) { throw 'Native command timeout was not enforced.' }

    $cmdDirectory = Join-Path $tempRoot 'command with spaces'
    New-Item -ItemType Directory -Path $cmdDirectory -Force | Out-Null
    $cmdPath = Join-Path $cmdDirectory 'echo arguments.cmd'
    [System.IO.File]::WriteAllText($cmdPath, "@echo off`r`necho %~1`r`n", [System.Text.Encoding]::ASCII)
    $cmdResult = Invoke-NativeCommand -FilePath $cmdPath -ArgumentList @('value with spaces') -Quiet
    if ($cmdResult.ExitCode -ne 0 -or $cmdResult.Text.Trim() -ne 'value with spaces') {
        throw "CMD wrapper argument quoting failed: $($cmdResult.Text)"
    }

    Initialize-SetupOutput -NoColor -OutputFormat Json
    $jsonLine = @(& { Write-SetupMessage -Message 'json-test' -Level Info -Event 'test-event' } 6>&1 | ForEach-Object { [string]$_ })[0]
    $json = $jsonLine | ConvertFrom-Json
    if ($json.event -ne 'test-event' -or $json.message -ne 'json-test') { throw 'JSON output is invalid.' }

    $pipelineResult = @(& {
        Write-SetupMessage -Message 'pipeline-test' -Level Info -Event 'pipeline-event'
        [pscustomobject]@{ ok = $true }
    })
    if ($pipelineResult.Count -ne 1 -or -not $pipelineResult[0].ok) { throw 'JSON output polluted a task result pipeline.' }

    Write-Host 'Runtime tests passed.'
}
finally { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
