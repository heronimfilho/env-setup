Set-StrictMode -Version Latest

$script:EnvSetupNoColor = $false
$script:EnvSetupOutputFormat = 'Text'
$script:EnvSetupLogPath = $null
$script:EnvSetupHeartbeatSeconds = 10
$script:EnvSetupCommandTimeoutSeconds = 0

function Initialize-SetupOutput {
    param(
        [switch]$NoColor,
        [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text',
        [string]$LogPath,
        [int]$HeartbeatSeconds = 10,
        [int]$CommandTimeoutSeconds = 0
    )
    $script:EnvSetupNoColor = [bool]$NoColor
    $script:EnvSetupOutputFormat = $OutputFormat
    $script:EnvSetupLogPath = $LogPath
    $script:EnvSetupHeartbeatSeconds = [Math]::Max(2, $HeartbeatSeconds)
    $script:EnvSetupCommandTimeoutSeconds = [Math]::Max(0, $CommandTimeoutSeconds)
}

function Write-SetupMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Muted')][string]$Level = 'Info',
        [string]$Event = 'message',
        $Data
    )
    $timestamp = (Get-Date).ToUniversalTime().ToString('o')
    if (-not [string]::IsNullOrWhiteSpace($script:EnvSetupLogPath)) {
        $directory = Split-Path -Parent $script:EnvSetupLogPath
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        Add-Content -LiteralPath $script:EnvSetupLogPath -Value ("{0} [{1}] {2}" -f $timestamp, $Level.ToUpperInvariant(), $Message) -Encoding UTF8
    }
    if ($script:EnvSetupOutputFormat -eq 'Json') {
        $payload = [ordered]@{ timestamp = $timestamp; event = $Event; level = $Level.ToLowerInvariant(); message = $Message }
        if ($null -ne $Data) { $payload.data = $Data }
        Write-Output ($payload | ConvertTo-Json -Depth 12 -Compress)
        return
    }
    if ($script:EnvSetupNoColor) { Write-Host $Message; return }
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Muted' { 'DarkGray' }
        default { 'Cyan' }
    }
    Write-Host $Message -ForegroundColor $color
}

function Write-SetupObject {
    param([Parameter(Mandatory = $true)]$Value, [string]$Event = 'result')
    if ($script:EnvSetupOutputFormat -eq 'Json') {
        Write-Output ([ordered]@{ timestamp = (Get-Date).ToUniversalTime().ToString('o'); event = $Event; data = $Value } | ConvertTo-Json -Depth 20 -Compress)
        return
    }
    $Value | Format-Table -AutoSize | Out-Host
}

function Write-MenuText {
    param([Parameter(Mandatory = $true)][string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    if ($script:EnvSetupNoColor) { Write-Host $Text } else { Write-Host $Text -ForegroundColor $Color }
}

function ConvertTo-NativeCommandLineArgument {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $backslashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) { [void]$builder.Append(('\' * $backslashes)); $backslashes = 0 }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$AllowFailure,
        [switch]$Quiet,
        [int]$TimeoutSeconds = $script:EnvSetupCommandTimeoutSeconds,
        [int]$HeartbeatSeconds = $script:EnvSetupHeartbeatSeconds
    )

    $command = Get-Command $FilePath -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw "Command not found: $FilePath" }
    $resolvedPath = if (-not [string]::IsNullOrWhiteSpace($command.Source)) { $command.Source } else { $command.Path }
    if ([string]::IsNullOrWhiteSpace($resolvedPath)) { $resolvedPath = $FilePath }

    $argumentString = (@($ArgumentList | ForEach-Object { ConvertTo-NativeCommandLineArgument -Value ([string]$_) }) -join ' ')
    if ([System.IO.Path]::GetExtension($resolvedPath) -in @('.cmd', '.bat')) {
        $scriptCommand = ('"{0}" {1}' -f $resolvedPath, $argumentString).Trim()
        $resolvedPath = if ([string]::IsNullOrWhiteSpace($env:ComSpec)) { 'cmd.exe' } else { $env:ComSpec }
        $argumentString = "/d /s /c " + (ConvertTo-NativeCommandLineArgument -Value $scriptCommand)
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-process-{0}" -f [guid]::NewGuid().ToString('N'))
    $stdoutPath = Join-Path $tempRoot 'stdout.txt'
    $stderrPath = Join-Path $tempRoot 'stderr.txt'
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastHeartbeat = [TimeSpan]::Zero
    $stdoutCount = 0
    $stderrCount = 0
    $process = $null

    try {
        $process = Start-Process -FilePath $resolvedPath -ArgumentList $argumentString -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        while (-not $process.WaitForExit(250)) {
            if ($TimeoutSeconds -gt 0 -and $stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                [void]$process.WaitForExit(5000)
                throw "Command timed out after $TimeoutSeconds seconds: $FilePath"
            }
            if (($stopwatch.Elapsed - $lastHeartbeat).TotalSeconds -ge $HeartbeatSeconds) {
                $lastHeartbeat = $stopwatch.Elapsed
                Write-SetupMessage -Message ("    Still working - {0:N0} seconds elapsed (PID {1})." -f $stopwatch.Elapsed.TotalSeconds, $process.Id) -Level Muted -Event 'heartbeat' -Data @{ pid = $process.Id; elapsedSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds) }
            }
            if (-not $Quiet) {
                $stdout = @(Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue)
                if ($stdout.Count -gt $stdoutCount) {
                    $stdout[$stdoutCount..($stdout.Count - 1)] | ForEach-Object { Write-SetupMessage -Message ("    {0}" -f $_) -Level Muted -Event 'process-output' }
                    $stdoutCount = $stdout.Count
                }
                $stderr = @(Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue)
                if ($stderr.Count -gt $stderrCount) {
                    $stderr[$stderrCount..($stderr.Count - 1)] | ForEach-Object { Write-SetupMessage -Message ("    {0}" -f $_) -Level Warning -Event 'process-error-output' }
                    $stderrCount = $stderr.Count
                }
            }
        }
        $process.WaitForExit()
        $process.Refresh()
        $exitCode = [int]$process.ExitCode
        $stopwatch.Stop()

        $stdout = @(Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue)
        $stderr = @(Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue)
        if (-not $Quiet) {
            if ($stdout.Count -gt $stdoutCount) { $stdout[$stdoutCount..($stdout.Count - 1)] | ForEach-Object { Write-SetupMessage -Message ("    {0}" -f $_) -Level Muted -Event 'process-output' } }
            if ($stderr.Count -gt $stderrCount) { $stderr[$stderrCount..($stderr.Count - 1)] | ForEach-Object { Write-SetupMessage -Message ("    {0}" -f $_) -Level Warning -Event 'process-error-output' } }
        }

        $output = @($stdout + $stderr)
        if ($exitCode -ne 0 -and -not $AllowFailure) {
            $message = if ($output.Count -gt 0) { $output -join [Environment]::NewLine } else { 'No output was returned.' }
            throw "$FilePath exited with code $exitCode.$([Environment]::NewLine)$message"
        }
        return [pscustomobject]@{
            ExitCode = $exitCode
            Output = $output
            Text = ($output -join [Environment]::NewLine)
            Duration = $stopwatch.Elapsed
            ProcessId = $process.Id
        }
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            [void]$process.WaitForExit(5000)
        }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-CodeCommand {
    param([Parameter(Mandatory = $true)][string[]]$ArgumentList, [switch]$AllowFailure, [switch]$Quiet)
    $code = Get-CodeCommand
    if ([string]::IsNullOrWhiteSpace($code)) { throw 'The Visual Studio Code command line was not found. Restart the terminal after installation and resume setup.' }
    return Invoke-NativeCommand -FilePath $code -ArgumentList $ArgumentList -AllowFailure:$AllowFailure -Quiet:$Quiet
}

function Show-MultiSelectMenu {
    param([Parameter(Mandatory = $true)][string]$Title, [Parameter(Mandatory = $true)][object[]]$Items)
    if ($script:EnvSetupOutputFormat -eq 'Json') { throw 'The interactive menu is not available with JSON output. Use -Profile, -Config, or -Include.' }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { throw 'The interactive menu requires a terminal. Use -Profile, -Include, or -Resume for non-interactive execution.' }

    $selected = @{}
    foreach ($item in $Items) { $selected[$item.Id] = [bool]$item.Selected }
    $index = 0
    $top = [Console]::CursorTop
    $previousCursorVisible = [Console]::CursorVisible
    [Console]::CursorVisible = $false

    try {
        while ($true) {
            [Console]::SetCursorPosition(0, $top)
            $count = @($Items | Where-Object { $selected[$_.Id] }).Count
            Write-MenuText -Text ("{0} ({1}/{2} selected)" -f $Title, $count, $Items.Count) -Color Cyan
            Write-MenuText -Text 'Up/Down move | Space toggle | A all | N none | D defaults | C Core | B Backend | F Full | S search | Enter continue' -Color DarkGray
            Write-Host ''
            for ($i = 0; $i -lt $Items.Count; $i++) {
                $item = $Items[$i]
                $cursor = if ($i -eq $index) { '>' } else { ' ' }
                $mark = if ($selected[$item.Id]) { 'x' } else { ' ' }
                $status = if ([string]::IsNullOrWhiteSpace($item.Status)) { '' } else { " [$($item.Status)]" }
                $dependency = if ([int]$item.DependencyCount -gt 0) { " (+$($item.DependencyCount) dependencies)" } else { '' }
                $line = "{0} [{1}] {2}{3}{4}" -f $cursor, $mark, $item.Label, $status, $dependency
                $padding = [Math]::Max(0, [Console]::WindowWidth - $line.Length - 1)
                Write-MenuText -Text ($line + (' ' * $padding)) -Color $(if ($i -eq $index) { 'White' } else { 'Gray' })
            }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow' { $index = if ($index -le 0) { $Items.Count - 1 } else { $index - 1 } }
                'DownArrow' { $index = if ($index -ge $Items.Count - 1) { 0 } else { $index + 1 } }
                'Spacebar' { $selected[$Items[$index].Id] = -not $selected[$Items[$index].Id] }
                'A' { foreach ($item in $Items) { $selected[$item.Id] = $true } }
                'N' { foreach ($item in $Items) { $selected[$item.Id] = $false } }
                'D' { foreach ($item in $Items) { $selected[$item.Id] = [bool]$item.Default } }
                'C' { foreach ($item in $Items) { $selected[$item.Id] = @($item.Profiles) -contains 'Core' } }
                'B' { foreach ($item in $Items) { $selected[$item.Id] = @($item.Profiles) -contains 'Backend' } }
                'F' { foreach ($item in $Items) { $selected[$item.Id] = @($item.Profiles) -contains 'Full' } }
                'S' {
                    [Console]::CursorVisible = $true
                    [Console]::SetCursorPosition(0, $top + $Items.Count + 3)
                    $term = Read-Host 'Search'
                    [Console]::CursorVisible = $false
                    if (-not [string]::IsNullOrWhiteSpace($term)) {
                        for ($offset = 1; $offset -le $Items.Count; $offset++) {
                            $candidate = ($index + $offset) % $Items.Count
                            if ($Items[$candidate].Label -like "*$term*") { $index = $candidate; break }
                        }
                    }
                }
            }
            if ($key.Key -eq 'Enter') { break }
        }
    }
    finally { [Console]::CursorVisible = $previousCursorVisible; Write-Host '' }
    return @($Items | Where-Object { $selected[$_.Id] } | ForEach-Object { $_.Id })
}

function Show-SetupPlanPreview {
    param(
        [Parameter(Mandatory = $true)][object[]]$Tasks,
        [Parameter(Mandatory = $true)][string[]]$SelectedTaskIds,
        [Parameter(Mandatory = $true)][string[]]$OrderedTaskIds,
        [switch]$NonInteractive
    )
    $taskMap = @{}; foreach ($task in $Tasks) { $taskMap[$task.Id] = $task }
    $dependencyIds = @($OrderedTaskIds | Where-Object { $_ -notin $SelectedTaskIds })
    $categories = @($OrderedTaskIds | ForEach-Object { $taskMap[$_].Category } | Group-Object | Sort-Object Name)
    $interactiveIds = @($OrderedTaskIds | Where-Object { $_ -in @('github.authenticate', 'ssh.windows-key', 'wsl.initialize') })
    $restartLikely = @($OrderedTaskIds | Where-Object { $_ -in @('wsl.install', 'windows.sandbox') }).Count -gt 0

    Write-SetupMessage -Message 'Plan summary' -Level Info -Event 'plan-summary'
    Write-SetupMessage -Message ("  Selected directly: {0}" -f $SelectedTaskIds.Count) -Level Muted
    Write-SetupMessage -Message ("  Total with dependencies: {0}" -f $OrderedTaskIds.Count) -Level Muted
    if ($dependencyIds.Count -gt 0) { Write-SetupMessage -Message ("  Added dependencies: {0}" -f ($dependencyIds -join ', ')) -Level Muted }
    foreach ($category in $categories) { Write-SetupMessage -Message ("  {0}: {1}" -f $category.Name, $category.Count) -Level Muted }
    Write-SetupMessage -Message ("  Interactive tasks: {0}" -f $interactiveIds.Count) -Level Muted
    Write-SetupMessage -Message ("  Restart may be required: {0}" -f $(if ($restartLikely) { 'yes' } else { 'no' })) -Level $(if ($restartLikely) { 'Warning' } else { 'Muted' })
    if (-not $NonInteractive -and -not [Console]::IsInputRedirected) {
        if (-not (Read-YesNo -Prompt 'Continue with this plan?' -Default $true)) { throw 'Setup cancelled by the user.' }
    }
}
