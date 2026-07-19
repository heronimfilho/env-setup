#requires -version 5.1

<#
.SYNOPSIS
Installs and configures a repeatable Windows development environment.

.DESCRIPTION
Provides an interactive task selector, reusable profiles, resumable execution, diagnostics,
status reporting, immutable self-updates, sanitized support bundles, and machine-readable output.

.EXAMPLE
.\setup.ps1
Opens the interactive selector and remembers the confirmed choices.

.EXAMPLE
.\setup.ps1 -Doctor
Checks Windows, WinGet, disk space, virtualization, WSL, pending restarts, and network access.

.EXAMPLE
.\setup.ps1 -Profile Backend -DryRun
Shows what the Backend profile would change without modifying the machine.

.EXAMPLE
.\setup.ps1 -Status -OutputFormat Json
Returns the persisted state of every task as JSON lines.

.EXAMPLE
.\setup.ps1 -Update
Downloads the latest immutable release snapshot and validates its SHA-256 before updating.
#>

[CmdletBinding()]
param(
    [ValidateSet('Interactive', 'Core', 'Backend', 'Full')][string]$Profile = 'Interactive',
    [string]$Config,
    [string[]]$Include = @(),
    [string[]]$Exclude = @(),
    [switch]$Resume,
    [switch]$Check,
    [switch]$DryRun,
    [switch]$Repair,
    [switch]$NonInteractive,
    [string]$GitName,
    [string]$GitEmail,
    [string]$WslDistribution = 'Ubuntu',
    [switch]$WslWebDownload,

    [switch]$Doctor,
    [switch]$DoctorSkipNetwork,
    [switch]$ListTasks,
    [switch]$Status,
    [string]$ExportConfig,
    [switch]$ResetSelections,
    [switch]$ShowLastLog,
    [switch]$CollectDiagnostics,
    [string]$DiagnosticsPath,
    [switch]$Update,
    [switch]$Version,
    [switch]$Force,

    [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text',
    [switch]$NoColor,
    [ValidateRange(2, 300)][int]$HeartbeatSeconds = 10,
    [ValidateRange(0, 86400)][int]$CommandTimeoutSeconds = 0,
    [switch]$SkipConfirmation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Runtime.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Selection.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Lock.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Windows.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Git.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.VSCode.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.WSL.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Shell.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.WindowsSettings.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Diagnostics.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Update.ps1')
# Load the task runner last so no feature module can replace its progress-aware functions.
. (Join-Path $PSScriptRoot 'src/EnvSetup.Progress.ps1')

if ($Check -and $DryRun) { throw 'Use either -Check or -DryRun, not both.' }
if ($Repair -and ($Check -or $DryRun)) { throw '-Repair cannot be combined with -Check or -DryRun.' }
if ($OutputFormat -eq 'Json' -and $Profile -eq 'Interactive' -and -not ($Doctor -or $ListTasks -or $Status -or $ExportConfig -or $ShowLastLog -or $CollectDiagnostics -or $Update -or $Version -or $ResetSelections)) {
    throw 'Interactive selection is not available with -OutputFormat Json. Use -Profile, -Config, -Include, or -Resume.'
}

$managementActionCount = @(
    [bool]$Doctor, [bool]$ListTasks, [bool]$Status, -not [string]::IsNullOrWhiteSpace($ExportConfig),
    [bool]$ResetSelections, [bool]$ShowLastLog, [bool]$CollectDiagnostics, [bool]$Update, [bool]$Version
) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
if ($managementActionCount -gt 1) { throw 'Use only one management command at a time: -Doctor, -ListTasks, -Status, -ExportConfig, -ResetSelections, -ShowLastLog, -CollectDiagnostics, -Update, or -Version.' }

$readOnly = [bool]($Check -or $DryRun -or $Doctor -or $ListTasks -or $Status -or $ExportConfig -or $ShowLastLog -or $CollectDiagnostics -or $Update -or $Version)
$paths = Initialize-EnvSetupStorage -ReadOnly:$readOnly
$logPath = if ($readOnly) { $null } else { $paths.LogPath }
Initialize-SetupOutput -NoColor:$NoColor -OutputFormat $OutputFormat -LogPath $logPath -HeartbeatSeconds $HeartbeatSeconds -CommandTimeoutSeconds $CommandTimeoutSeconds
Enter-EnvSetupLock -Paths $paths -ReadOnly:$readOnly

try {
    $state = Read-JsonFile -Path $paths.StatePath -DefaultValue (New-EnvSetupState)
    $tasks = @(
        Get-WindowsPackageTasks
        Get-GitTasks
        Get-VSCodeTasks
        Get-WslTasks
        Get-ShellTasks
        Get-WindowsSettingsTasks
    )

    $context = [pscustomobject]@{
        ProjectRoot     = $PSScriptRoot
        Paths           = $paths
        State           = $state
        Check           = [bool]$Check
        DryRun          = [bool]$DryRun
        Repair          = [bool]$Repair
        IsAdministrator = Test-IsAdministrator
        Options         = [pscustomobject]@{
            GitName         = $GitName
            GitEmail        = $GitEmail
            WslDistribution = $WslDistribution
            WslWebDownload  = [bool]$WslWebDownload
            NonInteractive  = [bool]$NonInteractive
        }
    }

    if ($Version) {
        Write-SetupObject -Value ([pscustomobject]@{ version = Get-EnvSetupVersion -ProjectRoot $PSScriptRoot }) -Event 'version'
        return
    }
    if ($ListTasks) {
        $catalog = @($tasks | ForEach-Object {
            [pscustomobject]@{ id = $_.Id; name = $_.Name; category = $_.Category; default = [bool]$_.Default; profiles = @($_.Profiles); dependencies = @($_.Dependencies); requiresAdmin = [bool]$_.RequiresAdmin }
        })
        Write-SetupObject -Value $catalog -Event 'task-catalog'
        return
    }
    if ($Doctor) {
        $doctorResult = Invoke-EnvSetupDoctor -SkipNetwork:$DoctorSkipNetwork
        $global:LASTEXITCODE = if ($doctorResult.healthy) { 0 } else { 1 }
        return
    }
    if ($Status) {
        Write-SetupObject -Value (Get-EnvSetupStatus -Paths $paths -Tasks $tasks) -Event 'status'
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($ExportConfig)) {
        [void](Export-EnvSetupPlan -Paths $paths -Destination $ExportConfig)
        return
    }
    if ($ResetSelections) {
        Reset-EnvSetupSelections -Paths $paths -Force:$Force
        return
    }
    if ($ShowLastLog) {
        Show-LastEnvSetupLog -Paths $paths
        return
    }
    if ($CollectDiagnostics) {
        [void](New-EnvSetupDiagnosticsBundle -Paths $paths -Tasks $tasks -ProjectRoot $PSScriptRoot -Destination $DiagnosticsPath)
        return
    }
    if ($Update) {
        [void](Invoke-EnvSetupUpdate -ProjectRoot $PSScriptRoot -Force:$Force)
        return
    }

    if (-not (Test-CommandAvailable -Name 'winget.exe')) {
        throw '[ENVSETUP-PREREQUISITE-WINGET] WinGet is required. Install or update App Installer from Microsoft Store, or run .\setup.ps1 -Doctor for details.'
    }

    $selectedTaskIds = @()
    $existingPlan = Read-JsonFile -Path $paths.PlanPath
    $savedPreferencePlan = Get-ValidatedSavedSetupPlan -Plan $existingPlan
    $requestedPlan = $null
    $usedInteractiveMenu = $false

    if (-not [string]::IsNullOrWhiteSpace($Config)) {
        $configPath = (Resolve-Path -LiteralPath $Config -ErrorAction Stop).Path
        $requestedPlan = Read-JsonFile -Path $configPath
        if ($null -eq $requestedPlan) { throw 'The configuration file is empty.' }
        Assert-SetupPlanSchema -Plan $requestedPlan
    }

    if ($Resume) {
        if ($null -eq $savedPreferencePlan) { throw 'No valid saved setup plan was found.' }
        $requestedPlan = $savedPreferencePlan
        $selectedTaskIds = @($savedPreferencePlan.selectedTasks)
    }
    elseif ($null -ne $requestedPlan) { $selectedTaskIds = @($requestedPlan.selectedTasks) }
    elseif ($Include.Count -gt 0) { $selectedTaskIds = @($Include) }
    elseif ($Profile -ne 'Interactive') { $selectedTaskIds = @($tasks | Where-Object { $_.Profiles -contains $Profile } | ForEach-Object { $_.Id }) }
    else {
        if ($NonInteractive) { throw 'Use -Profile, -Config, or -Include with -NonInteractive.' }
        $usedInteractiveMenu = $true
        if ($null -ne $savedPreferencePlan) { Write-SetupMessage -Message 'Loaded the selections from the previous interactive run.' -Level Muted }
        $menuItems = Get-InteractiveTaskMenuItems -Tasks $tasks -Context $context -SavedPlan $savedPreferencePlan
        $selectedTaskIds = Show-MultiSelectMenu -Title 'Select the components to install and configure' -Items $menuItems
    }

    $optionPlan = if ($null -ne $requestedPlan) { $requestedPlan } elseif ($usedInteractiveMenu) { $savedPreferencePlan } else { $null }
    Set-SetupOptionsFromPlan -Context $context -Plan $optionPlan -ExplicitOptionNames @($PSBoundParameters.Keys)
    $usingSavedPreferences = $usedInteractiveMenu -and $null -ne $savedPreferencePlan

    $knownTaskIds = @($tasks | ForEach-Object { $_.Id })
    $unknownTaskIds = @($selectedTaskIds | Where-Object { $_ -notin $knownTaskIds })
    $unknownExclusions = @($Exclude | Where-Object { $_ -notin $knownTaskIds })
    if ($unknownTaskIds.Count -gt 0) { throw "Unknown task IDs: $($unknownTaskIds -join ', ')" }
    if ($unknownExclusions.Count -gt 0) { throw "Unknown excluded task IDs: $($unknownExclusions -join ', ')" }

    $selectedTaskIds = @($selectedTaskIds | Where-Object { $_ -notin $Exclude } | Select-Object -Unique)
    if ($selectedTaskIds.Count -eq 0) { Write-SetupMessage -Message 'No components were selected.' -Level Warning; return }

    $orderedTaskIds = @(Resolve-TaskOrder -Tasks $tasks -SelectedTaskIds $selectedTaskIds)
    Assert-NoExcludedTaskDependencies -OrderedTaskIds $orderedTaskIds -ExcludedTaskIds $Exclude

    $requiresGitIdentity = @($orderedTaskIds | Where-Object { $_ -in @('git.windows-config', 'git.wsl-config', 'ssh.windows-key', 'ssh.github-upload') }).Count -gt 0
    if ($requiresGitIdentity) {
        if ([string]::IsNullOrWhiteSpace($context.Options.GitName)) { $context.Options.GitName = Get-GitConfigValue -Key 'user.name' }
        if ([string]::IsNullOrWhiteSpace($context.Options.GitEmail)) { $context.Options.GitEmail = Get-GitConfigValue -Key 'user.email' }
        $hasGitIdentity = -not [string]::IsNullOrWhiteSpace($context.Options.GitName) -and -not [string]::IsNullOrWhiteSpace($context.Options.GitEmail)
        $canPrompt = -not $NonInteractive -and -not [Console]::IsInputRedirected
        if ($canPrompt -and (-not $usingSavedPreferences -or -not $hasGitIdentity)) {
            $context.Options.GitName = Read-RequiredValue -Prompt 'Git user name' -DefaultValue $context.Options.GitName
            $context.Options.GitEmail = Read-RequiredValue -Prompt 'Git email' -DefaultValue $context.Options.GitEmail
        }
        elseif (-not $hasGitIdentity) { throw 'Git identity is required. Provide -GitName and -GitEmail.' }
    }

    $requiresWsl = @($orderedTaskIds | Where-Object { $_ -like 'wsl.*' -or $_ -like 'git.wsl-*' }).Count -gt 0
    if ($requiresWsl -and -not $NonInteractive -and -not $Resume -and $null -eq $requestedPlan -and -not $usingSavedPreferences -and -not [Console]::IsInputRedirected) {
        $context.Options.WslDistribution = Read-RequiredValue -Prompt 'WSL distribution' -DefaultValue $context.Options.WslDistribution
    }
    if ($requiresWsl -and -not (Test-WslDistributionSupported -Distribution $context.Options.WslDistribution)) {
        throw "Unsupported WSL distribution '$($context.Options.WslDistribution)'. Supported distributions: $((Get-SupportedWslDistributions) -join ', ')."
    }

    if ($NonInteractive -and -not $Check -and -not $DryRun) {
        $taskMap = @{}; foreach ($task in $tasks) { $taskMap[$task.Id] = $task }
        foreach ($interactiveTaskId in @('github.authenticate', 'ssh.windows-key', 'wsl.initialize')) {
            if ($orderedTaskIds -notcontains $interactiveTaskId) { continue }
            $configured = $false
            try { $configured = [bool](& $taskMap[$interactiveTaskId].Detect $context) } catch { $configured = $false }
            if ($Repair -or -not $configured) { throw "Task '$interactiveTaskId' requires interactive input and cannot run with -NonInteractive. Configure it interactively, then resume." }
        }
    }

    if (-not $SkipConfirmation -and -not $Check -and -not $DryRun) {
        Show-SetupPlanPreview -Tasks $tasks -SelectedTaskIds $selectedTaskIds -OrderedTaskIds $orderedTaskIds -NonInteractive:$NonInteractive
    }

    $plan = [pscustomobject]@{
        schemaVersion = 1
        createdAt     = (Get-Date).ToUniversalTime().ToString('o')
        profile       = $Profile
        selectedTasks = $selectedTaskIds
        options       = $context.Options
    }
    if (-not $readOnly) { Write-JsonFileAtomic -Value $plan -Path $paths.PlanPath }

    Write-SetupMessage -Message "Selected tasks: $($selectedTaskIds.Count)" -Level Info
    if ($DryRun) { Write-SetupMessage -Message 'Dry-run mode is enabled.' -Level Muted }
    if ($Check) { Write-SetupMessage -Message 'Check mode is enabled.' -Level Muted }

    [void](Invoke-SetupPlan -Tasks $tasks -SelectedTaskIds $selectedTaskIds -Context $context)
    Write-SetupMessage -Message 'Environment setup finished.' -Level Success -Event 'setup-finished'
}
finally { Exit-EnvSetupLock -Paths $paths }
