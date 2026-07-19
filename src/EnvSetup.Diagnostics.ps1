Set-StrictMode -Version Latest

function Get-EnvSetupVersion {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'VERSION'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '0.0.0-dev' }
    return (Get-Content -LiteralPath $path -Raw).Trim()
}

function Test-PendingWindowsReboot {
    foreach ($path in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )) {
        if (Test-Path -LiteralPath $path) { return $true }
    }
    try {
        $pending = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop
        if ($null -ne $pending.PendingFileRenameOperations) { return $true }
    }
    catch { }
    return $false
}

function New-DoctorCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [ValidateSet('pass', 'warning', 'fail')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Details,
        [Parameter(Mandatory = $true)][string]$Code
    )
    return [pscustomobject]@{ name = $Name; status = $Status; details = $Details; code = $Code }
}

function Get-EnvSetupDoctorChecks {
    param([switch]$SkipNetwork)

    $checks = New-Object System.Collections.Generic.List[object]
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $supported = [int]$os.BuildNumber -ge 19041
        $checks.Add((New-DoctorCheck -Name 'Windows version' -Status $(if ($supported) { 'pass' } else { 'fail' }) -Details ("{0}, build {1}" -f $os.Caption, $os.BuildNumber) -Code 'ENVSETUP-DOCTOR-WINDOWS'))
    }
    catch { $checks.Add((New-DoctorCheck -Name 'Windows version' -Status 'warning' -Details $_.Exception.Message -Code 'ENVSETUP-DOCTOR-WINDOWS')) }

    $isAdmin = Test-IsAdministrator
    $checks.Add((New-DoctorCheck -Name 'Administrator session' -Status $(if ($isAdmin) { 'pass' } else { 'warning' }) -Details $(if ($isAdmin) { 'PowerShell is elevated.' } else { 'Installation tasks may require an elevated PowerShell session.' }) -Code 'ENVSETUP-DOCTOR-ADMIN'))
    $checks.Add((New-DoctorCheck -Name 'PowerShell' -Status 'pass' -Details ("PowerShell {0}" -f $PSVersionTable.PSVersion) -Code 'ENVSETUP-DOCTOR-POWERSHELL'))

    $policy = Get-ExecutionPolicy
    $checks.Add((New-DoctorCheck -Name 'Execution policy' -Status $(if ($policy -eq 'Restricted') { 'warning' } else { 'pass' }) -Details ([string]$policy) -Code 'ENVSETUP-DOCTOR-POLICY'))

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    $checks.Add((New-DoctorCheck -Name 'WinGet' -Status $(if ($null -ne $winget) { 'pass' } else { 'fail' }) -Details $(if ($null -ne $winget) { $winget.Source } else { 'App Installer/WinGet was not found.' }) -Code 'ENVSETUP-DOCTOR-WINGET'))

    try {
        $driveName = ([System.IO.Path]::GetPathRoot($HOME)).TrimEnd('\').TrimEnd(':')
        $drive = Get-PSDrive -Name $driveName -ErrorAction Stop
        $freeGb = [Math]::Round($drive.Free / 1GB, 1)
        $diskStatus = if ($freeGb -ge 15) { 'pass' } elseif ($freeGb -ge 5) { 'warning' } else { 'fail' }
        $checks.Add((New-DoctorCheck -Name 'Free disk space' -Status $diskStatus -Details ("{0} GB available on {1}:" -f $freeGb, $driveName) -Code 'ENVSETUP-DOCTOR-DISK'))
    }
    catch { $checks.Add((New-DoctorCheck -Name 'Free disk space' -Status 'warning' -Details $_.Exception.Message -Code 'ENVSETUP-DOCTOR-DISK')) }

    $pendingReboot = Test-PendingWindowsReboot
    $checks.Add((New-DoctorCheck -Name 'Pending restart' -Status $(if ($pendingReboot) { 'warning' } else { 'pass' }) -Details $(if ($pendingReboot) { 'Windows reports a pending restart.' } else { 'No pending restart was detected.' }) -Code 'ENVSETUP-DOCTOR-REBOOT'))

    try {
        $processors = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
        $virtualization = @($processors | Where-Object { $_.VirtualizationFirmwareEnabled }).Count -gt 0
        $checks.Add((New-DoctorCheck -Name 'Firmware virtualization' -Status $(if ($virtualization) { 'pass' } else { 'warning' }) -Details $(if ($virtualization) { 'Enabled.' } else { 'Not reported as enabled; WSL 2 and Sandbox may fail.' }) -Code 'ENVSETUP-DOCTOR-VIRTUALIZATION'))
    }
    catch { $checks.Add((New-DoctorCheck -Name 'Firmware virtualization' -Status 'warning' -Details $_.Exception.Message -Code 'ENVSETUP-DOCTOR-VIRTUALIZATION')) }

    Write-SetupMessage -Message '  Checking WSL status...' -Level Muted -Event 'doctor-check-start' -Data @{ check = 'wsl' }
    try {
        $wslStatus = Invoke-NativeCommand -FilePath 'wsl.exe' -ArgumentList @('--status') -AllowFailure -Quiet -TimeoutSeconds 30
        $wslDetails = if ([string]::IsNullOrWhiteSpace($wslStatus.Text)) { "Exit code $($wslStatus.ExitCode)." } else { ($wslStatus.Text -replace '\s+', ' ').Trim() }
        $checks.Add((New-DoctorCheck -Name 'WSL command' -Status $(if ($wslStatus.ExitCode -eq 0) { 'pass' } else { 'warning' }) -Details $wslDetails -Code 'ENVSETUP-DOCTOR-WSL'))
    }
    catch { $checks.Add((New-DoctorCheck -Name 'WSL command' -Status 'warning' -Details $_.Exception.Message -Code 'ENVSETUP-DOCTOR-WSL')) }

    if (-not $SkipNetwork) {
        foreach ($endpoint in @(
            @{ Name = 'GitHub'; Host = 'github.com' },
            @{ Name = 'Microsoft downloads'; Host = 'aka.ms' },
            @{ Name = 'WinGet CDN'; Host = 'cdn.winget.microsoft.com' }
        )) {
            Write-SetupMessage -Message ("  Checking {0} connectivity..." -f $endpoint.Name) -Level Muted -Event 'doctor-check-start' -Data @{ check = 'network'; host = $endpoint.Host }
            try {
                $reachable = Test-NetConnection -ComputerName $endpoint.Host -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
                $codeSuffix = ($endpoint.Name -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
                $checks.Add((New-DoctorCheck -Name ("Network: {0}" -f $endpoint.Name) -Status $(if ($reachable) { 'pass' } else { 'fail' }) -Details ("{0}:443" -f $endpoint.Host) -Code ("ENVSETUP-DOCTOR-NETWORK-{0}" -f $codeSuffix)))
            }
            catch { $checks.Add((New-DoctorCheck -Name ("Network: {0}" -f $endpoint.Name) -Status 'warning' -Details $_.Exception.Message -Code 'ENVSETUP-DOCTOR-NETWORK')) }
        }
    }

    return $checks.ToArray()
}

function New-EnvSetupDoctorResult {
    param([Parameter(Mandatory = $true)][object[]]$Checks)
    $failed = @($Checks | Where-Object status -eq 'fail')
    $warnings = @($Checks | Where-Object status -eq 'warning')
    return [pscustomobject]@{ checks = $Checks; healthy = ($failed.Count -eq 0); failures = $failed.Count; warnings = $warnings.Count }
}

function Invoke-EnvSetupDoctor {
    param([switch]$SkipNetwork)
    Write-SetupMessage -Message 'Running environment diagnostics...' -Level Info -Event 'doctor-start'
    $checks = @(Get-EnvSetupDoctorChecks -SkipNetwork:$SkipNetwork)
    Write-SetupObject -Value $checks -Event 'doctor-result'
    $result = New-EnvSetupDoctorResult -Checks $checks
    $passedCount = @($checks | Where-Object status -eq 'pass').Count
    Write-SetupMessage -Message ("Doctor result: {0} passed, {1} warnings, {2} failures." -f $passedCount, $result.warnings, $result.failures) -Level $(if ($result.failures -gt 0) { 'Error' } elseif ($result.warnings -gt 0) { 'Warning' } else { 'Success' }) -Event 'doctor-summary'
    return $result
}

function Get-EnvSetupStatus {
    param([Parameter(Mandatory = $true)]$Paths, [Parameter(Mandatory = $true)][object[]]$Tasks)
    $state = Read-JsonFile -Path $Paths.StatePath -DefaultValue (New-EnvSetupState)
    $plan = Read-JsonFile -Path $Paths.PlanPath
    $selected = if ($null -eq $plan) { @() } else { @($plan.selectedTasks) }
    return @(
        foreach ($task in $Tasks) {
            $entry = Get-StateTask -State $state -TaskId $task.Id
            [pscustomobject]@{
                id = $task.Id
                name = $task.Name
                category = $task.Category
                selected = $selected -contains $task.Id
                status = if ($null -eq $entry) { 'not-run' } else { [string]$entry.status }
                phase = if ($null -eq $entry -or $null -eq $entry.details) { '' } else { [string](Get-OptionalPropertyValue -Object $entry.details -Name 'phase' -DefaultValue '') }
                updatedAt = if ($null -eq $entry) { $null } else { $entry.updatedAt }
                message = if ($null -eq $entry) { '' } else { [string](Get-OptionalPropertyValue -Object $entry -Name 'message' -DefaultValue '') }
            }
        }
    )
}

function Export-EnvSetupPlan {
    param([Parameter(Mandatory = $true)]$Paths, [Parameter(Mandatory = $true)][string]$Destination)
    if (-not (Test-Path -LiteralPath $Paths.PlanPath -PathType Leaf)) { throw 'No saved setup plan was found.' }
    $resolvedDestination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    $directory = Split-Path -Parent $resolvedDestination
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    Copy-Item -LiteralPath $Paths.PlanPath -Destination $resolvedDestination -Force
    Write-SetupMessage -Message "Saved setup plan exported to: $resolvedDestination" -Level Success -Event 'plan-exported'
    return $resolvedDestination
}

function Reset-EnvSetupSelections {
    param([Parameter(Mandatory = $true)]$Paths, [switch]$Force)
    if (-not (Test-Path -LiteralPath $Paths.PlanPath -PathType Leaf)) { Write-SetupMessage -Message 'No saved selections exist.' -Level Muted; return }
    if (-not $Force -and -not [Console]::IsInputRedirected -and -not (Read-YesNo -Prompt 'Remove the saved interactive selections?' -Default $false)) {
        Write-SetupMessage -Message 'Saved selections were not changed.' -Level Muted
        return
    }
    Remove-Item -LiteralPath $Paths.PlanPath -Force
    Write-SetupMessage -Message 'Saved interactive selections were reset. The next interactive run will use defaults.' -Level Success -Event 'selections-reset'
}

function Show-LastEnvSetupLog {
    param([Parameter(Mandatory = $true)]$Paths)
    $logDirectory = Join-Path $Paths.RootPath 'logs'
    $log = Get-ChildItem -LiteralPath $logDirectory -Filter '*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($null -eq $log) { throw 'No setup log was found.' }
    $content = Get-Content -LiteralPath $log.FullName -Raw
    if ($script:EnvSetupOutputFormat -eq 'Json') {
        Write-SetupObject -Value ([pscustomobject]@{ path = $log.FullName; content = $content }) -Event 'last-log'
        return
    }
    Write-SetupMessage -Message "Last log: $($log.FullName)" -Level Info
    Write-Host $content
}

function Protect-DiagnosticText {
    param([AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    $result = $Text
    if (-not [string]::IsNullOrWhiteSpace($HOME)) { $result = $result.Replace($HOME, '%USERPROFILE%') }
    $result = [regex]::Replace($result, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '<redacted-email>')
    $result = [regex]::Replace($result, '(?i)("(?:token|password|secret|passphrase)"\s*:\s*")[^"]*(")', '$1<redacted>$2')
    $result = [regex]::Replace($result, "(?i)('(?:token|password|secret|passphrase)'\s*:\s*')[^']*(')", '$1<redacted>$2')
    $result = [regex]::Replace($result, '(?i)((?:token|password|secret|passphrase)\s*[:=]\s*)(?:"[^"]*"|''[^'']*''|\S+)', '$1<redacted>')
    $result = [regex]::Replace($result, '(?i)(authorization\s*:\s*(?:bearer|basic)\s+)\S+', '$1<redacted>')
    $result = [regex]::Replace($result, '\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b', '<redacted-token>')
    $result = [regex]::Replace($result, '\b(?:AKIA|ASIA)[A-Z0-9]{16}\b', '<redacted-access-key>')
    $result = [regex]::Replace($result, '-----BEGIN [^-]+ PRIVATE KEY-----[\s\S]*?-----END [^-]+ PRIVATE KEY-----', '<redacted-private-key>')
    return $result
}

function New-EnvSetupDiagnosticsBundle {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][object[]]$Tasks,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$Destination,
        [switch]$SkipNetwork
    )

    if ([string]::IsNullOrWhiteSpace($Destination)) { $Destination = Join-Path $HOME ("env-setup-diagnostics-{0}.zip" -f (Get-Date -Format 'yyyyMMdd-HHmmss')) }
    $Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    $destinationDirectory = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destinationDirectory)) { New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-diagnostics-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        $doctorChecks = @(Get-EnvSetupDoctorChecks -SkipNetwork:$SkipNetwork)
        $doctor = New-EnvSetupDoctorResult -Checks $doctorChecks
        $status = Get-EnvSetupStatus -Paths $Paths -Tasks $Tasks
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'doctor.json'), ($doctor | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'status.json'), ($status | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'version.txt'), (Get-EnvSetupVersion -ProjectRoot $ProjectRoot), [System.Text.UTF8Encoding]::new($false))

        if (Test-Path -LiteralPath $Paths.PlanPath -PathType Leaf) {
            [System.IO.File]::WriteAllText((Join-Path $tempRoot 'plan.redacted.json'), (Protect-DiagnosticText -Text (Get-Content -LiteralPath $Paths.PlanPath -Raw)), [System.Text.UTF8Encoding]::new($false))
        }
        if (Test-Path -LiteralPath $Paths.StatePath -PathType Leaf) {
            [System.IO.File]::WriteAllText((Join-Path $tempRoot 'state.redacted.json'), (Protect-DiagnosticText -Text (Get-Content -LiteralPath $Paths.StatePath -Raw)), [System.Text.UTF8Encoding]::new($false))
        }
        $log = Get-ChildItem -LiteralPath (Join-Path $Paths.RootPath 'logs') -Filter '*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if ($null -ne $log) {
            [System.IO.File]::WriteAllText((Join-Path $tempRoot 'last-log.redacted.txt'), (Protect-DiagnosticText -Text (Get-Content -LiteralPath $log.FullName -Raw)), [System.Text.UTF8Encoding]::new($false))
        }

        if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
        Compress-Archive -Path (Join-Path $tempRoot '*') -DestinationPath $Destination -Force
        if (-not (Test-Path -LiteralPath $Destination -PathType Leaf) -or (Get-Item -LiteralPath $Destination).Length -eq 0) { throw 'The diagnostics archive was not created correctly.' }
        Write-SetupMessage -Message "Sanitized diagnostics bundle created: $Destination" -Level Success -Event 'diagnostics-created'
        return $Destination
    }
    finally { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
