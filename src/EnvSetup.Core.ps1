Set-StrictMode -Version Latest

function Write-SetupMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Muted')][string]$Level = 'Info'
    )

    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Muted' { 'DarkGray' }
        default { 'Cyan' }
    }

    Write-Host $Message -ForegroundColor $color
}

function Get-EnvSetupDataPath {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is not available.'
    }

    return Join-Path $env:LOCALAPPDATA 'env-setup'
}

function Initialize-EnvSetupStorage {
    param([string]$RootPath = (Get-EnvSetupDataPath))

    foreach ($directory in @(
        $RootPath,
        (Join-Path $RootPath 'backups'),
        (Join-Path $RootPath 'logs')
    )) {
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
    }

    return [pscustomobject]@{
        RootPath  = $RootPath
        PlanPath  = Join-Path $RootPath 'plan.json'
        StatePath = Join-Path $RootPath 'state.json'
        LockPath  = Join-Path $RootPath 'lock.json'
        LogPath   = Join-Path (Join-Path $RootPath 'logs') ("{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        $DefaultValue = $null
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $DefaultValue
    }

    $content = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $DefaultValue
    }

    return $content | ConvertFrom-Json
}

function Write-JsonFileAtomic {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $temporaryPath = Join-Path $directory (".{0}.{1}.tmp" -f (Split-Path -Leaf $Path), [guid]::NewGuid().ToString('N'))
    $json = $Value | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function New-EnvSetupState {
    return [pscustomobject]@{
        schemaVersion = 1
        updatedAt     = (Get-Date).ToUniversalTime().ToString('o')
        tasks         = [pscustomobject]@{}
    }
}

function Get-StateTask {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$TaskId
    )

    if ($null -eq $State.tasks) {
        return $null
    }

    $property = $State.tasks.PSObject.Properties[$TaskId]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Set-StateTask {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Message,
        [hashtable]$Details
    )

    $entry = [ordered]@{
        status    = $Status
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    }

    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $entry.message = $Message
    }

    if ($null -ne $Details) {
        $entry.details = [pscustomobject]$Details
    }

    $State.tasks | Add-Member -NotePropertyName $TaskId -NotePropertyValue ([pscustomobject]$entry) -Force
    $State.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$AllowFailure,
        [switch]$Quiet
    )

    if (-not (Test-CommandAvailable -Name $FilePath)) {
        throw "Command not found: $FilePath"
    }

    $output = @(& $FilePath @ArgumentList 2>&1)
    $exitCode = $LASTEXITCODE

    if (-not $Quiet) {
        $output | ForEach-Object { Write-Host $_ }
    }

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $message = if ($output.Count -gt 0) { ($output -join [Environment]::NewLine) } else { 'No output was returned.' }
        throw "$FilePath exited with code $exitCode.$([Environment]::NewLine)$message"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $output
        Text     = ($output -join [Environment]::NewLine)
    }
}

function Read-RequiredValue {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [string]$DefaultValue
    )

    while ($true) {
        $suffix = if ([string]::IsNullOrWhiteSpace($DefaultValue)) { '' } else { " [$DefaultValue]" }
        $value = Read-Host "$Prompt$suffix"
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = $DefaultValue
        }

        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }

        Write-SetupMessage -Message 'A value is required.' -Level Warning
    }
}

function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [bool]$Default = $true
    )

    $choice = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = (Read-Host "$Prompt $choice").Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }
        if ($answer -in @('y', 'yes')) { return $true }
        if ($answer -in @('n', 'no')) { return $false }
        Write-SetupMessage -Message 'Enter yes or no.' -Level Warning
    }
}

function Show-MultiSelectMenu {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][object[]]$Items
    )

    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'The interactive menu requires a terminal. Use -Profile, -Include, or -Resume for non-interactive execution.'
    }

    $selected = @{}
    foreach ($item in $Items) {
        $selected[$item.Id] = [bool]$item.Selected
    }

    $index = 0
    $top = [Console]::CursorTop
    $previousCursorVisible = [Console]::CursorVisible
    [Console]::CursorVisible = $false

    try {
        while ($true) {
            [Console]::SetCursorPosition(0, $top)
            Write-Host $Title -ForegroundColor Cyan
            Write-Host 'Use Up/Down to move, Space to toggle, A to select all, N to clear, Enter to continue.' -ForegroundColor DarkGray
            Write-Host ''

            for ($i = 0; $i -lt $Items.Count; $i++) {
                $item = $Items[$i]
                $cursor = if ($i -eq $index) { '>' } else { ' ' }
                $mark = if ($selected[$item.Id]) { 'x' } else { ' ' }
                $status = if ([string]::IsNullOrWhiteSpace($item.Status)) { '' } else { " [$($item.Status)]" }
                $line = "{0} [{1}] {2}{3}" -f $cursor, $mark, $item.Label, $status
                $padding = [Math]::Max(0, [Console]::WindowWidth - $line.Length - 1)
                $lineColor = if ($i -eq $index) { 'White' } else { 'Gray' }
                Write-Host ($line + (' ' * $padding)) -ForegroundColor $lineColor
            }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow' { $index = if ($index -le 0) { $Items.Count - 1 } else { $index - 1 } }
                'DownArrow' { $index = if ($index -ge $Items.Count - 1) { 0 } else { $index + 1 } }
                'Spacebar' { $selected[$Items[$index].Id] = -not $selected[$Items[$index].Id] }
                'A' { foreach ($item in $Items) { $selected[$item.Id] = $true } }
                'N' { foreach ($item in $Items) { $selected[$item.Id] = $false } }
            }

            if ($key.Key -eq 'Enter') {
                break
            }
        }
    }
    finally {
        [Console]::CursorVisible = $previousCursorVisible
        Write-Host ''
    }

    return @($Items | Where-Object { $selected[$_.Id] } | ForEach-Object { $_.Id })
}

function Resolve-TaskOrder {
    param(
        [Parameter(Mandatory = $true)][object[]]$Tasks,
        [Parameter(Mandatory = $true)][string[]]$SelectedTaskIds
    )

    $taskMap = @{}
    foreach ($task in $Tasks) {
        $taskMap[$task.Id] = $task
    }

    $resolved = New-Object System.Collections.Generic.List[string]
    $visiting = @{}
    $visited = @{}

    function Visit-Task {
        param([string]$TaskId)

        if ($visited[$TaskId]) { return }
        if ($visiting[$TaskId]) { throw "Circular task dependency detected at $TaskId." }
        if (-not $taskMap.ContainsKey($TaskId)) { throw "Unknown task dependency: $TaskId" }

        $visiting[$TaskId] = $true
        foreach ($dependency in @($taskMap[$TaskId].Dependencies)) {
            Visit-Task -TaskId $dependency
        }
        $visiting.Remove($TaskId)
        $visited[$TaskId] = $true
        $resolved.Add($TaskId)
    }

    foreach ($taskId in $SelectedTaskIds) {
        Visit-Task -TaskId $taskId
    }

    return @($resolved)
}

function Invoke-SetupTask {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)]$Context
    )

    $taskId = $Task.Id
    Write-SetupMessage -Message "[$taskId] $($Task.Name)" -Level Info

    try {
        $alreadyConfigured = [bool](& $Task.Detect $Context)
        if ($alreadyConfigured -and -not $Context.Repair) {
            Set-StateTask -State $Context.State -TaskId $taskId -Status 'completed' -Message 'Already configured.'
            Write-JsonFileAtomic -Value $Context.State -Path $Context.Paths.StatePath
            Write-SetupMessage -Message 'Already configured.' -Level Success
            return
        }

        if ($Context.Check) {
            $status = if ($alreadyConfigured) { 'configured' } else { 'missing' }
            $level = if ($alreadyConfigured) { 'Success' } else { 'Warning' }
            Write-SetupMessage -Message "Status: $status" -Level $level
            return
        }

        if ($Context.DryRun) {
            Write-SetupMessage -Message 'Planned; no changes were made.' -Level Muted
            return
        }

        if ($Task.RequiresAdmin -and -not $Context.IsAdministrator) {
            throw 'This task requires an elevated PowerShell session.'
        }

        Set-StateTask -State $Context.State -TaskId $taskId -Status 'running'
        Write-JsonFileAtomic -Value $Context.State -Path $Context.Paths.StatePath
        & $Task.Apply $Context

        if (-not [bool](& $Task.Verify $Context)) {
            throw 'Verification failed after applying the task.'
        }

        Set-StateTask -State $Context.State -TaskId $taskId -Status 'completed'
        Write-JsonFileAtomic -Value $Context.State -Path $Context.Paths.StatePath
        Write-SetupMessage -Message 'Completed.' -Level Success
    }
    catch {
        Set-StateTask -State $Context.State -TaskId $taskId -Status 'failed' -Message $_.Exception.Message
        Write-JsonFileAtomic -Value $Context.State -Path $Context.Paths.StatePath
        Write-SetupMessage -Message $_.Exception.Message -Level Error
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

    $orderedTaskIds = Resolve-TaskOrder -Tasks $Tasks -SelectedTaskIds $SelectedTaskIds
    foreach ($taskId in $orderedTaskIds) {
        Invoke-SetupTask -Task $taskMap[$taskId] -Context $Context
    }
}
