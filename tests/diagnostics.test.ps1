#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Runtime.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Diagnostics.ps1')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-diagnostics-test-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    Initialize-SetupOutput -NoColor
    $paths = Initialize-EnvSetupStorage -RootPath (Join-Path $tempRoot 'stateful')
    $plan = [pscustomobject]@{ schemaVersion = 1; selectedTasks = @('test.one'); options = [pscustomobject]@{ GitEmail = 'person@example.com' } }
    Write-JsonFileAtomic -Value $plan -Path $paths.PlanPath
    $state = New-EnvSetupState
    Set-StateTask -State $state -TaskId 'test.one' -Status 'completed' -Details @{ result = 'completed' }
    Write-JsonFileAtomic -Value $state -Path $paths.StatePath
    $tasks = @([pscustomobject]@{ Id = 'test.one'; Name = 'Test one'; Category = 'Tests' })

    $status = @(Get-EnvSetupStatus -Paths $paths -Tasks $tasks)
    if ($status.Count -ne 1 -or -not $status[0].selected -or $status[0].status -ne 'completed') { throw 'Status reporting did not combine plan and state.' }

    $exportPath = Join-Path $tempRoot 'exported.json'
    [void](Export-EnvSetupPlan -Paths $paths -Destination $exportPath)
    if (-not (Test-Path -LiteralPath $exportPath)) { throw 'Plan export did not create the destination file.' }

    $sensitiveText = @'
user=person@example.com password=plain-secret
{"password":"json-secret","token":"json-token"}
Authorization: Bearer authorization-secret
'@
    $protected = Protect-DiagnosticText -Text $sensitiveText
    foreach ($sensitiveValue in @('person@example.com', 'plain-secret', 'json-secret', 'json-token', 'authorization-secret')) {
        if ($protected.Contains($sensitiveValue)) { throw "Diagnostic sanitization did not redact: $sensitiveValue" }
    }
    if ($protected -notmatch '<redacted-email>' -or $protected -notmatch '<redacted>') { throw 'Diagnostic sanitization did not include redaction markers.' }

    function Get-EnvSetupDoctorChecks {
        param([switch]$SkipNetwork)
        return @([pscustomobject]@{ name = 'Test'; status = 'pass'; details = 'ok'; code = 'ENVSETUP-DOCTOR-TEST' })
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $paths.LogPath) -Force | Out-Null
    Set-Content -LiteralPath $paths.LogPath -Value 'email=person@example.com password=secret'
    $bundlePath = Join-Path $tempRoot 'diagnostics.zip'
    [void](New-EnvSetupDiagnosticsBundle -Paths $paths -Tasks $tasks -ProjectRoot $projectRoot -Destination $bundlePath -SkipNetwork)
    if (-not (Test-Path -LiteralPath $bundlePath -PathType Leaf)) { throw 'Diagnostics bundle was not created.' }

    $expandedPath = Join-Path $tempRoot 'expanded'
    Expand-Archive -LiteralPath $bundlePath -DestinationPath $expandedPath
    foreach ($required in @('doctor.json', 'status.json', 'version.txt', 'plan.redacted.json', 'state.redacted.json', 'last-log.redacted.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $expandedPath $required) -PathType Leaf)) { throw "Diagnostics bundle is missing: $required" }
    }
    $redactedLog = Get-Content -LiteralPath (Join-Path $expandedPath 'last-log.redacted.txt') -Raw
    if ($redactedLog -match 'person@example.com|password=secret') { throw 'Diagnostics bundle contains unredacted sensitive values.' }

    Initialize-SetupOutput -NoColor -OutputFormat Json
    $jsonLog = @(& { Show-LastEnvSetupLog -Paths $paths } 6>&1 | ForEach-Object { [string]$_ })
    if ($jsonLog.Count -ne 1 -or ($jsonLog[0] | ConvertFrom-Json).event -ne 'last-log') { throw 'JSON last-log output is not a single valid event.' }

    Initialize-SetupOutput -NoColor -OutputFormat Text
    Reset-EnvSetupSelections -Paths $paths -Force
    if (Test-Path -LiteralPath $paths.PlanPath) { throw 'Reset selections did not remove plan.json.' }

    Write-Host 'Diagnostics tests passed.'
}
finally { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
