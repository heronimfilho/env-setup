#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-tests-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $paths = Initialize-EnvSetupStorage -RootPath $tempRoot
    $state = New-EnvSetupState
    $marker = Join-Path $tempRoot 'marker.txt'

    $context = [pscustomobject]@{
        Paths           = $paths
        State           = $state
        Check           = $false
        DryRun          = $false
        Repair          = $false
        IsAdministrator = $true
        Options         = [pscustomobject]@{}
    }

    $task = [pscustomobject]@{
        Id            = 'test.success'
        Name          = 'Successful test task'
        RequiresAdmin = $false
        Dependencies  = @()
        Detect        = { param($Context) Test-Path -LiteralPath $marker }.GetNewClosure()
        Apply         = { param($Context) Set-Content -LiteralPath $marker -Value 'ok' }.GetNewClosure()
        Verify        = { param($Context) (Get-Content -LiteralPath $marker -Raw).Trim() -eq 'ok' }.GetNewClosure()
    }

    Invoke-SetupTask -Task $task -Context $context
    Invoke-SetupTask -Task $task -Context $context

    $savedState = Read-JsonFile -Path $paths.StatePath
    if ((Get-StateTask -State $savedState -TaskId 'test.success').status -ne 'completed') {
        throw 'Completed task state was not persisted.'
    }

    $failureTask = [pscustomobject]@{
        Id            = 'test.failure'
        Name          = 'Failing test task'
        RequiresAdmin = $false
        Dependencies  = @()
        Detect        = { param($Context) $false }
        Apply         = { param($Context) throw 'Expected failure.' }
        Verify        = { param($Context) $false }
    }

    try {
        Invoke-SetupTask -Task $failureTask -Context $context
        throw 'The failing task did not fail.'
    }
    catch {
        if ($_.Exception.Message -eq 'The failing task did not fail.') { throw }
    }

    $savedState = Read-JsonFile -Path $paths.StatePath
    if ((Get-StateTask -State $savedState -TaskId 'test.failure').status -ne 'failed') {
        throw 'Failed task state was not persisted.'
    }

    $dependencyTask = [pscustomobject]@{ Id = 'test.dependency'; Dependencies = @() }
    $dependentTask = [pscustomobject]@{ Id = 'test.dependent'; Dependencies = @('test.dependency') }
    $order = Resolve-TaskOrder -Tasks @($dependentTask, $dependencyTask) -SelectedTaskIds @('test.dependent')
    if (($order -join ',') -ne 'test.dependency,test.dependent') {
        throw 'Task dependencies were not ordered correctly.'
    }

    Write-Host 'Core tests passed.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
