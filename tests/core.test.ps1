#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Selection.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Lock.ps1')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-tests-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $readOnlyRoot = Join-Path $tempRoot 'read-only'
    $readOnlyPaths = Initialize-EnvSetupStorage -RootPath $readOnlyRoot -ReadOnly
    if (Test-Path -LiteralPath $readOnlyRoot) {
        throw 'Read-only storage initialization created a directory.'
    }

    Enter-EnvSetupLock -Paths $readOnlyPaths -ReadOnly
    if (Test-Path -LiteralPath $readOnlyPaths.LockPath) {
        throw 'A read-only lock created lock.json.'
    }
    Exit-EnvSetupLock -Paths $readOnlyPaths

    $paths = Initialize-EnvSetupStorage -RootPath (Join-Path $tempRoot 'stateful')

    Write-JsonFileAtomic -Value ([pscustomobject]@{ processId = 2147483647 }) -Path $paths.LockPath
    Enter-EnvSetupLock -Paths $paths
    $activeLock = Read-JsonFile -Path $paths.LockPath
    if ([int]$activeLock.processId -ne $PID) {
        throw 'A stale setup lock was not replaced.'
    }

    $secondLockFailed = $false
    try {
        Enter-EnvSetupLock -Paths $paths
    }
    catch {
        $secondLockFailed = $true
    }
    if (-not $secondLockFailed) {
        throw 'A concurrent setup lock was accepted.'
    }
    Exit-EnvSetupLock -Paths $paths
    if (Test-Path -LiteralPath $paths.LockPath) {
        throw 'The setup lock was not removed.'
    }

    Assert-SetupPlanSchema -Plan ([pscustomobject]@{ selectedTasks = @('test.success') })

    $schemaFailed = $false
    try {
        Assert-SetupPlanSchema -Plan ([pscustomobject]@{ schemaVersion = 2; selectedTasks = @('test.success') })
    }
    catch {
        $schemaFailed = $true
    }
    if (-not $schemaFailed) {
        throw 'An unsupported plan schema version was accepted.'
    }

    $invalidSavedPlan = Get-ValidatedSavedSetupPlan -Plan ([pscustomobject]@{ schemaVersion = 2; selectedTasks = @('test.success') })
    if ($null -ne $invalidSavedPlan) {
        throw 'An invalid saved plan was accepted as an interactive preference.'
    }

    $menuTasks = @(
        [pscustomobject]@{
            Id = 'test.default'; Name = 'Default task'; Category = 'Tests'; Default = $true
            Detect = { param($Context) $true }
        },
        [pscustomobject]@{
            Id = 'test.optional'; Name = 'Optional task'; Category = 'Tests'; Default = $false
            Detect = { param($Context) $false }
        }
    )
    $savedMenuPlan = [pscustomobject]@{
        selectedTasks = @('test.optional')
        options = [pscustomobject]@{
            GitName = 'Saved Developer'
            GitEmail = 'saved@example.com'
            WslDistribution = 'Debian'
            WslWebDownload = $true
        }
    }
    $savedMenuItems = Get-InteractiveTaskMenuItems -Tasks $menuTasks -Context ([pscustomobject]@{}) -SavedPlan $savedMenuPlan
    if (($savedMenuItems | Where-Object Id -eq 'test.default').Selected) {
        throw 'A previously deselected default task was selected again.'
    }
    if (-not ($savedMenuItems | Where-Object Id -eq 'test.optional').Selected) {
        throw 'A previously selected optional task was not restored.'
    }
    if (($savedMenuItems | Where-Object Id -eq 'test.default').Status -ne 'configured') {
        throw 'Interactive menu task status detection failed.'
    }

    $defaultMenuItems = Get-InteractiveTaskMenuItems -Tasks $menuTasks -Context ([pscustomobject]@{}) -SavedPlan $null
    if (-not ($defaultMenuItems | Where-Object Id -eq 'test.default').Selected) {
        throw 'Default selections were not used without a saved plan.'
    }
    if (($defaultMenuItems | Where-Object Id -eq 'test.optional').Selected) {
        throw 'An optional task was selected without a saved plan.'
    }

    $preferenceContext = [pscustomobject]@{
        Options = [pscustomobject]@{
            GitName = $null
            GitEmail = $null
            WslDistribution = 'Ubuntu-24.04'
            WslWebDownload = $false
        }
    }
    Set-SetupOptionsFromPlan -Context $preferenceContext -Plan $savedMenuPlan -ExplicitOptionNames @('WslDistribution')
    if ($preferenceContext.Options.GitName -ne 'Saved Developer' -or $preferenceContext.Options.GitEmail -ne 'saved@example.com') {
        throw 'Saved Git identity options were not restored.'
    }
    if ($preferenceContext.Options.WslDistribution -ne 'Ubuntu-24.04') {
        throw 'An explicit WSL distribution was overwritten by saved preferences.'
    }
    if (-not $preferenceContext.Options.WslWebDownload) {
        throw 'The saved WSL web-download preference was not restored.'
    }

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

    $stateBeforeInspection = Get-Content -LiteralPath $paths.StatePath -Raw
    $context.Check = $true
    Invoke-SetupTask -Task $task -Context $context
    $context.Check = $false
    $context.DryRun = $true
    Invoke-SetupTask -Task $task -Context $context
    $context.DryRun = $false
    $stateAfterInspection = Get-Content -LiteralPath $paths.StatePath -Raw
    if ($stateBeforeInspection -ne $stateAfterInspection) {
        throw 'Check or dry-run mode modified state.json.'
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

    $excludeFailed = $false
    try {
        Assert-NoExcludedTaskDependencies -OrderedTaskIds $order -ExcludedTaskIds @('test.dependency')
    }
    catch {
        $excludeFailed = $true
    }
    if (-not $excludeFailed) {
        throw 'An excluded transitive dependency was accepted.'
    }

    Write-Host 'Core tests passed.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
