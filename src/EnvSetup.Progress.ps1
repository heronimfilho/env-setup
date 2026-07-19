Set-StrictMode -Version Latest

function Format-SetupDuration {
    param([Parameter(Mandatory = $true)][TimeSpan]$Elapsed)
    if ($Elapsed.TotalSeconds -lt 1) { return ("{0} ms" -f [Math]::Max(1, [Math]::Round($Elapsed.TotalMilliseconds))) }
    if ($Elapsed.TotalMinutes -lt 1) { return ("{0:N1} s" -f $Elapsed.TotalSeconds) }
    return ("{0}m {1}s" -f [Math]::Floor($Elapsed.TotalMinutes), $Elapsed.Seconds)
}

function Get-SetupErrorCode {
    param([Parameter(Mandatory = $true)][string]$TaskId, [Parameter(Mandatory = $true)][string]$Phase)
    $taskPart = ($TaskId -replace '[^A-Za-z0-9]+', '-').Trim('-').ToUpperInvariant()
    $phasePart = ($Phase -replace '[^A-Za-z0-9]+', '-').Trim('-').ToUpperInvariant()
    return "ENVSETUP-$taskPart-$phasePart"
}

function Invoke-TaskOperation {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Detect', 'Apply', 'Verify')][string]$Operation
    )
    $defaultMessage = switch ($Operation) {
        'Detect' { 'Checking the current state...' }
        'Apply' { 'Applying the required changes...' }
        'Verify' { 'Verifying the resulting state...' }
    }
    $message = Get-OptionalPropertyValue -Object $Task -Name ("{0}Message" -f $Operation) -DefaultValue $defaultMessage
    $operationLabel = switch ($Operation) {
        'Detect' { 'State check' }
        'Apply' { 'Apply phase' }
        'Verify' { 'Verification' }
    }

    Write-SetupMessage -Message ("  {0}" -f $message) -Level Muted -Event ('task-' + $Operation.ToLowerInvariant() + '-start') -Data @{ taskId = $Task.Id }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $commandProperty = $Task.PSObject.Properties[$Operation]
    if ($null -eq $commandProperty -or $commandProperty.Value -isnot [scriptblock]) { throw "Task '$($Task.Id)' does not define a valid $Operation operation." }
    $result = & $commandProperty.Value $Context
    $stopwatch.Stop()
    Write-SetupMessage -Message ("  {0} finished in {1}." -f $operationLabel, (Format-SetupDuration -Elapsed $stopwatch.Elapsed)) -Level Muted -Event ('task-' + $Operation.ToLowerInvariant() + '-complete') -Data @{ taskId = $Task.Id; elapsedMilliseconds = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds) }
    return $result
}

function Set-TaskExecutionPhase {
    param([Parameter(Mandatory = $true)]$Context, [Parameter(Mandatory = $true)][string]$TaskId, [Parameter(Mandatory = $true)][string]$Phase)
    if ($Context.Check -or $Context.DryRun) { return }
    Set-StateTask -State $Context.State -TaskId $TaskId -Status 'running' -Details @{ phase = $Phase }
    Write-JsonFileAtomic -Value $Context.State -Path $Context.Paths.StatePath
}

function New-TaskResult {
    param([string]$TaskId, [string]$Name, [string]$Status, [TimeSpan]$Duration, [string]$Phase, [string]$ErrorCode, [string]$Message)
    return [pscustomobject]@{
        taskId = $TaskId
        name = $Name
        status = $Status
        durationMilliseconds = [Math]::Round($Duration.TotalMilliseconds)
        phase = $Phase
        errorCode = $ErrorCode
        message = $Message
    }
}

function Invoke-SetupTask {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)]$Context,
        [int]$Position = 0,
        [int]$Total = 0
    )
    $taskId = $Task.Id
    $prefix = if ($Position -gt 0 -and $Total -gt 0) { "[$Position/$Total] " } else { '' }
    Write-SetupMessage -Message ("{0}[{1}] {2}" -f $prefix, $taskId, $Task.Name) -Level Info -Event 'task-start' -Data @{ taskId = $taskId; position = $Position; total = $Total }

    $taskStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $currentPhase = 'state-check'
    try {
        Set-TaskExecutionPhase -Context $Context -TaskId $taskId -Phase 'checking'
        $alreadyConfigured = [bool](Invoke-TaskOperation -Task $Task -Context $Context -Operation Detect)
        Write-SetupMessage -Message $(if ($alreadyConfigured) { '  Current state: configured.' } else { '  Current state: missing or incomplete.' }) -Level $(if ($alreadyConfigured) { 'Success' } else { 'Warning' }) -Event 'task-state' -Data @{ taskId = $taskId; configured = $alreadyConfigured }

        if ($Context.Check) {
            $taskStopwatch.Stop()
            $status = if ($alreadyConfigured) { 'configured' } else { 'missing' }
            Write-SetupMessage -Message ("  Status: {0}. Task inspection took {1}." -f $status, (Format-SetupDuration -Elapsed $taskStopwatch.Elapsed)) -Level $(if ($alreadyConfigured) { 'Success' } else { 'Warning' })
            return New-TaskResult -TaskId $taskId -Name $Task.Name -Status $status -Duration $taskStopwatch.Elapsed -Phase $currentPhase
        }
        if ($Context.DryRun) {
            $taskStopwatch.Stop()
            $status = if ($alreadyConfigured -and -not $Context.Repair) { 'already-configured' } else { 'planned' }
            Write-SetupMessage -Message $(if ($status -eq 'already-configured') { "  Already configured; no changes were made. Checked in $(Format-SetupDuration -Elapsed $taskStopwatch.Elapsed)." } else { "  Planned; no changes were made. Checked in $(Format-SetupDuration -Elapsed $taskStopwatch.Elapsed)." }) -Level $(if ($status -eq 'already-configured') { 'Success' } else { 'Muted' })
            return New-TaskResult -TaskId $taskId -Name $Task.Name -Status $status -Duration $taskStopwatch.Elapsed -Phase $currentPhase
        }
        if ($alreadyConfigured -and -not $Context.Repair) {
            Set-StateTask -State $Context.State -TaskId $taskId -Status 'completed' -Message 'Already configured.' -Details @{ result = 'already-configured' }
            Write-JsonFileAtomic -Value $Context.State -Path $Context.Paths.StatePath
            $taskStopwatch.Stop()
            Write-SetupMessage -Message ("  Already configured. Completed in {0}." -f (Format-SetupDuration -Elapsed $taskStopwatch.Elapsed)) -Level Success -Event 'task-complete'
            return New-TaskResult -TaskId $taskId -Name $Task.Name -Status 'already-configured' -Duration $taskStopwatch.Elapsed -Phase $currentPhase
        }
        if ($alreadyConfigured -and $Context.Repair) { Write-SetupMessage -Message '  Repair mode is enabled; the configured task will be applied again.' -Level Warning }
        if ($Task.RequiresAdmin -and -not $Context.IsAdministrator) { throw 'This task requires an elevated PowerShell session.' }

        $currentPhase = 'apply'
        Set-TaskExecutionPhase -Context $Context -TaskId $taskId -Phase 'applying'
        Invoke-TaskOperation -Task $Task -Context $Context -Operation Apply | Out-Null
        $currentPhase = 'verification'
        Set-TaskExecutionPhase -Context $Context -TaskId $taskId -Phase 'verifying'
        if (-not [bool](Invoke-TaskOperation -Task $Task -Context $Context -Operation Verify)) { throw 'Verification failed after applying the task.' }

        Set-StateTask -State $Context.State -TaskId $taskId -Status 'completed' -Details @{ result = 'completed' }
        Write-JsonFileAtomic -Value $Context.State -Path $Context.Paths.StatePath
        $taskStopwatch.Stop()
        Write-SetupMessage -Message ("  Completed successfully in {0}." -f (Format-SetupDuration -Elapsed $taskStopwatch.Elapsed)) -Level Success -Event 'task-complete'
        return New-TaskResult -TaskId $taskId -Name $Task.Name -Status 'completed' -Duration $taskStopwatch.Elapsed -Phase $currentPhase
    }
    catch {
        $taskStopwatch.Stop()
        $errorCode = Get-SetupErrorCode -TaskId $taskId -Phase $currentPhase
        if (-not $Context.Check -and -not $Context.DryRun) {
            Set-StateTask -State $Context.State -TaskId $taskId -Status 'failed' -Message $_.Exception.Message -Details @{ phase = $currentPhase; errorCode = $errorCode }
            Write-JsonFileAtomic -Value $Context.State -Path $Context.Paths.StatePath
        }
        Write-SetupMessage -Message ("  [{0}] Task failed during {1} after {2}: {3}" -f $errorCode, $currentPhase, (Format-SetupDuration -Elapsed $taskStopwatch.Elapsed), $_.Exception.Message) -Level Error -Event 'task-failed' -Data @{ taskId = $taskId; phase = $currentPhase; errorCode = $errorCode }
        $_.Exception.Data['EnvSetupTaskResult'] = New-TaskResult -TaskId $taskId -Name $Task.Name -Status 'failed' -Duration $taskStopwatch.Elapsed -Phase $currentPhase -ErrorCode $errorCode -Message $_.Exception.Message
        throw
    }
}

function Get-SetupResultCount {
    param([Parameter(Mandatory = $true)][hashtable]$Counts, [Parameter(Mandatory = $true)][string]$Status)
    if (-not $Counts.ContainsKey($Status)) { return 0 }
    return [int]$Counts[$Status]
}

function Show-SetupExecutionSummary {
    param(
        [Parameter(Mandatory = $true)][object[]]$Results,
        [Parameter(Mandatory = $true)][TimeSpan]$Duration,
        [Parameter(Mandatory = $true)]$Context,
        [switch]$Failed
    )
    $counts = @{}
    foreach ($result in $Results) {
        if (-not $counts.ContainsKey($result.status)) { $counts[$result.status] = 0 }
        $counts[$result.status]++
    }
    $rebootRequired = @($Results | Where-Object { $_.taskId -in @('wsl.install', 'windows.sandbox') -and $_.status -eq 'completed' }).Count -gt 0 -or (Test-PendingWindowsReboot)
    $summary = [pscustomobject]@{
        completed = Get-SetupResultCount -Counts $counts -Status 'completed'
        alreadyConfigured = Get-SetupResultCount -Counts $counts -Status 'already-configured'
        planned = Get-SetupResultCount -Counts $counts -Status 'planned'
        configured = Get-SetupResultCount -Counts $counts -Status 'configured'
        missing = Get-SetupResultCount -Counts $counts -Status 'missing'
        failed = Get-SetupResultCount -Counts $counts -Status 'failed'
        durationMilliseconds = [Math]::Round($Duration.TotalMilliseconds)
        rebootRequired = $rebootRequired
        logPath = $Context.Paths.LogPath
    }

    Write-SetupMessage -Message 'Setup summary' -Level Info -Event 'setup-summary' -Data $summary
    Write-SetupMessage -Message ("  Completed: {0}" -f $summary.completed) -Level Success
    Write-SetupMessage -Message ("  Already configured: {0}" -f $summary.alreadyConfigured) -Level Success
    if ($Context.DryRun) { Write-SetupMessage -Message ("  Planned: {0}" -f $summary.planned) -Level Muted }
    if ($Context.Check) { Write-SetupMessage -Message ("  Configured: {0}; missing: {1}" -f $summary.configured, $summary.missing) -Level Muted }
    Write-SetupMessage -Message ("  Failed: {0}" -f $summary.failed) -Level $(if ($summary.failed -gt 0) { 'Error' } else { 'Success' })
    Write-SetupMessage -Message ("  Duration: {0}" -f (Format-SetupDuration -Elapsed $Duration)) -Level Muted
    Write-SetupMessage -Message ("  Restart required: {0}" -f $(if ($rebootRequired) { 'yes' } else { 'no' })) -Level $(if ($rebootRequired) { 'Warning' } else { 'Muted' })
    if (-not [string]::IsNullOrWhiteSpace($Context.Paths.LogPath)) { Write-SetupMessage -Message ("  Log: {0}" -f $Context.Paths.LogPath) -Level Muted }
    if ($Failed -or $rebootRequired) { Write-SetupMessage -Message '  Continue with: .\setup.ps1 -Resume' -Level Warning }
    return $summary
}

function Invoke-SetupPlan {
    param([Parameter(Mandatory = $true)][object[]]$Tasks, [Parameter(Mandatory = $true)][string[]]$SelectedTaskIds, [Parameter(Mandatory = $true)]$Context)
    $taskMap = @{}; foreach ($task in $Tasks) { $taskMap[$task.Id] = $task }
    $orderedTaskIds = @(Resolve-TaskOrder -Tasks $Tasks -SelectedTaskIds $SelectedTaskIds)
    $results = New-Object System.Collections.Generic.List[object]
    $planStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-SetupMessage -Message ("Starting setup plan with {0} task(s)." -f $orderedTaskIds.Count) -Level Info -Event 'setup-start' -Data @{ taskCount = $orderedTaskIds.Count }
    try {
        for ($index = 0; $index -lt $orderedTaskIds.Count; $index++) {
            $taskId = $orderedTaskIds[$index]
            $results.Add((Invoke-SetupTask -Task $taskMap[$taskId] -Context $Context -Position ($index + 1) -Total $orderedTaskIds.Count))
        }
        $planStopwatch.Stop()
        $summary = Show-SetupExecutionSummary -Results $results.ToArray() -Duration $planStopwatch.Elapsed -Context $Context
        return [pscustomobject]@{ results = $results.ToArray(); summary = $summary }
    }
    catch {
        $planStopwatch.Stop()
        $failedResult = $_.Exception.Data['EnvSetupTaskResult']
        if ($null -ne $failedResult) { $results.Add($failedResult) }
        [void](Show-SetupExecutionSummary -Results $results.ToArray() -Duration $planStopwatch.Elapsed -Context $Context -Failed)
        throw
    }
}
