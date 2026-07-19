#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Progress.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.TaskFactories.ps1')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-progress-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $paths = Initialize-EnvSetupStorage -RootPath (Join-Path $tempRoot 'state')
    $marker = Join-Path $tempRoot 'installed.txt'
    $state = New-EnvSetupState
    $context = [pscustomobject]@{
        Paths           = $paths
        State           = $state
        Check           = $false
        DryRun          = $false
        Repair          = $false
        IsAdministrator = $true
        Options         = [pscustomobject]@{}
    }

    $installTask = [pscustomobject]@{
        Id            = 'test.install'
        Name          = 'Install test component'
        RequiresAdmin = $false
        Dependencies  = @()
        DetectMessage = 'Checking the test component...'
        ApplyMessage  = 'Applying the test component...'
        VerifyMessage = 'Verifying the test component...'
        Detect        = { param($Context) Test-Path -LiteralPath $marker }.GetNewClosure()
        Apply         = { param($Context) Set-Content -LiteralPath $marker -Value 'installed' }.GetNewClosure()
        Verify        = { param($Context) (Get-Content -LiteralPath $marker -Raw).Trim() -eq 'installed' }.GetNewClosure()
    }
    $readyTask = [pscustomobject]@{
        Id            = 'test.ready'
        Name          = 'Already ready component'
        RequiresAdmin = $false
        Dependencies  = @()
        Detect        = { param($Context) $true }
        Apply         = { param($Context) throw 'Apply should not run for an already configured task.' }
        Verify        = { param($Context) $true }
    }

    $messages = @(& {
        Invoke-SetupPlan -Tasks @($installTask, $readyTask) -SelectedTaskIds @('test.install', 'test.ready') -Context $context
    } 6>&1 | ForEach-Object { [string]$_ })
    $text = $messages -join "`n"

    foreach ($expected in @(
        'Starting setup plan with 2 task(s).',
        '[1/2] [test.install] Install test component',
        'Checking the test component...',
        'Current state: missing or incomplete.',
        'Applying the test component...',
        'Verifying the test component...',
        '[2/2] [test.ready] Already ready component',
        'Current state: configured.',
        'Already configured.'
    )) {
        if (-not $text.Contains($expected)) {
            throw "Progress output is missing: $expected`n$text"
        }
    }

    if ($text -notmatch 'finished in \d') {
        throw "Progress output does not include elapsed phase timing.`n$text"
    }

    $failureTask = [pscustomobject]@{
        Id            = 'test.verify-failure'
        Name          = 'Verification failure component'
        RequiresAdmin = $false
        Dependencies  = @()
        Detect        = { param($Context) $false }
        Apply         = { param($Context) $null }
        Verify        = { param($Context) $false }
    }
    try {
        Invoke-SetupTask -Task $failureTask -Context $context | Out-Null
        throw 'The verification failure task did not fail.'
    }
    catch {
        if ($_.Exception.Message -eq 'The verification failure task did not fail.') { throw }
    }

    $failureState = Get-StateTask -State (Read-JsonFile -Path $paths.StatePath) -TaskId 'test.verify-failure'
    if ($failureState.status -ne 'failed' -or $failureState.details.phase -ne 'verification') {
        throw 'The failed task did not persist its active execution phase.'
    }

    $wingetTask = New-WingetTask -Id 'test.winget' -Name 'Test Package' -Category 'Tests' -PackageId 'Example.Package'
    foreach ($propertyName in @('DetectMessage', 'ApplyMessage', 'VerifyMessage')) {
        $message = [string]$wingetTask.PSObject.Properties[$propertyName].Value
        if ($message -notmatch 'Example\.Package') {
            throw "WinGet task progress message does not identify the package: $propertyName"
        }
    }
    if ($wingetTask.DetectMessage -notmatch 'first WinGet query' -or $wingetTask.DetectMessage -notmatch 'wait for the state-check result') {
        throw 'The WinGet detection message does not explain the first-query wait state.'
    }

    Write-Host 'Progress reporting tests passed.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
