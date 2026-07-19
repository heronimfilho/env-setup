Set-StrictMode -Version Latest

function Format-SetupDuration {
    param([Parameter(Mandatory = $true)][TimeSpan]$Elapsed)

    if ($Elapsed.TotalSeconds -lt 1) {
        return ("{0} ms" -f [Math]::Max(1, [Math]::Round($Elapsed.TotalMilliseconds)))
    }
    if ($Elapsed.TotalMinutes -lt 1) {
        return ("{0:N1} s" -f $Elapsed.TotalSeconds)
    }

    return ("{0}m {1}s" -f [Math]::Floor($Elapsed.TotalMinutes), $Elapsed.Seconds)
}

function Invoke-TaskOperation {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Detect', 'Apply', 'Verify')]
        [string]$Operation
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

    Write-SetupMessage -Message ("  {0}" -f $message) -Level Muted
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $command = $Task.PSObject.Properties[$Operation].Value
        $result = & $command $Context
        $stopwatch.Stop()
        Write-SetupMessage -Message ("  {0} finished in {1}." -f $operationLabel, (Format-SetupDuration -Elapsed $stopwatch.Elapsed)) -Level Muted
        return $result
    }
    catch {
        $stopwatch.Stop()
        Write-SetupMessage -Message ("  {0} failed after {1}." -f $operationLabel, (Format-SetupDuration -Elapsed $stopwatch.Elapsed)) -Level Error
        throw
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
    Write-SetupMessage -Message ("{0}[{1}] {2}" -f $prefix, $taskId, $Task.Name) -Level Info

    $taskStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $currentPhase = 'state check'

    try {
        $alreadyConfigured = [bool](Invoke-TaskOperation -Task $Task -Context $Context -Operation Detect)
        if ($alreadyConfigured) {
            Write-SetupMessage -Message '  Current state: configured.' -Level Success
        }
        else {
            Write-SetupMessage -Message '  Current state: missing or incomplete.' -Level Warning
        }

        if ($Context.Check) {
            $taskStopwatch.Stop()
            $status = if ($alreadyConfigured) { 'configured' } else { 'missing' }
            $level = if ($alreadyConfigured) { 'Success' } else { 'Warning' }
            Write-SetupMessage -Message ("  Status: {0}. Task inspection took {1}." -f $status, (Format-SetupDuration -Elapsed $taskStopwatch.Elapsed)) -Level $level
            return
        }

        if ($Context.DryRun) {
            $taskStopwatch.Stop()
            if ($alreadyConfigured -and -not $Context.Repair) {
                Write-SetupMessage -Message ("  Already configured; no changes were made. Checked in {0}." -f (Format-SetupDuration -Elapsed $taskStopwatch.Elapsed)) -Level Success
            }
            else {
                Write-SetupMessage -Message ("  Planned; no changes were made. Checked in {0}." -f (Format-SetupDuration -Elapsed $taskStopwatch.Elapsed)) -Level Muted
            }
            return
        }

        if ($alreadyConfigured -and -not $Context.Repair) {
            Set-StateTask -State $Context.State -TaskId $taskId -Status 'completed' -Message 'Already configured.'
            Write-JsonFileAtomic -Value $Context.State -Path $Context.Paths.StatePath
            $taskStopwatch.Stop()
            Write-SetupMessage -Message ("  Already configured. Completed in {0}." -f (Format-SetupDuration -Elapsed $taskStopwatch.Elapsed)) -Level Success
            return
        }

        if ($Task.RequiresAdmin -and -not $Context.IsAdministrator) {
            throw 'This task requires an elevated PowerShell session.'
        }

        Set-StateTask -State $Context.State -TaskId $taskId -Status 'running'
        Write-JsonFileAtomic -Value $Context.State -Path $Context.Paths.StatePath

        $currentPhase = 'apply phase'
        Invoke-TaskOperation -Task $Task -Context $Context -Operation Apply | Out-Null

        $currentPhase = 'verification'
        if (-not [bool](Invoke-TaskOperation -Task $Task -Context $Context -Operation Verify)) {
            throw 'Verification failed after applying the task.'
        }

        Set-StateTask -State $Context.State -TaskId $taskId -Status 'completed'
        Write-JsonFileAtomic -Value $Context.State -Path $Context.Paths.StatePath
        $taskStopwatch.Stop()
        Write-SetupMessage -Message ("  Completed successfully in {0}." -f (Format-SetupDuration -Elapsed $taskStopwatch.Elapsed)) -Level Success
    }
    catch {
        $taskStopwatch.Stop()
        if (-not $Context.Check -and -not $Context.DryRun) {
            Set-StateTask -State $Context.State -TaskId $taskId -Status 'failed' -Message $_.Exception.Message
            Write-JsonFileAtomic -Value $Context.State -Path $Context.Paths.StatePath
        }
        Write-SetupMessage -Message ("  Task failed during {0} after {1}: {2}" -f $currentPhase, (Format-SetupDuration -Elapsed $taskStopwatch.Elapsed), $_.Exception.Message) -Level Error
        throw
    }
}

function Invoke-SetupPlan {
    param(
        [Parameter(Mandatory = $true)][object[]]$Tasks,
        [Parameter(Mandatory = $true)][string[]]$SelectedTaskIds,
        [Parameter(Mandatory = $true)]$Context
    )

    $taskMap = @{}
    foreach ($task in $Tasks) {
        $taskMap[$task.Id] = $task
    }

    $orderedTaskIds = @(Resolve-TaskOrder -Tasks $Tasks -SelectedTaskIds $SelectedTaskIds)
    Write-SetupMessage -Message ("Starting setup plan with {0} task(s)." -f $orderedTaskIds.Count) -Level Info

    for ($index = 0; $index -lt $orderedTaskIds.Count; $index++) {
        $taskId = $orderedTaskIds[$index]
        Invoke-SetupTask -Task $taskMap[$taskId] -Context $Context -Position ($index + 1) -Total $orderedTaskIds.Count
    }
}
