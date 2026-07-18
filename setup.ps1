#requires -version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Interactive', 'Core', 'Backend', 'Full')]
    [string]$Profile = 'Interactive',
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
    [switch]$WslWebDownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Lock.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Windows.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Git.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.VSCode.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.WSL.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Shell.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.WindowsSettings.ps1')

$paths = Initialize-EnvSetupStorage
Enter-EnvSetupLock -Paths $paths

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

    if (-not (Test-CommandAvailable -Name 'winget.exe')) {
        throw 'WinGet is required. Install or update App Installer from Microsoft Store and run setup again.'
    }

    $selectedTaskIds = @()
    $existingPlan = Read-JsonFile -Path $paths.PlanPath
    $requestedPlan = $null

    if (-not [string]::IsNullOrWhiteSpace($Config)) {
        $configPath = (Resolve-Path -LiteralPath $Config -ErrorAction Stop).Path
        $requestedPlan = Read-JsonFile -Path $configPath
        if ($null -eq $requestedPlan -or $null -eq $requestedPlan.selectedTasks) {
            throw 'The configuration file must contain a selectedTasks array.'
        }
    }

    if ($Resume) {
        if ($null -eq $existingPlan) {
            throw 'No saved setup plan was found.'
        }
        $requestedPlan = $existingPlan
        $selectedTaskIds = @($existingPlan.selectedTasks)
    }
    elseif ($null -ne $requestedPlan) {
        $selectedTaskIds = @($requestedPlan.selectedTasks)
    }
    elseif ($Include.Count -gt 0) {
        $selectedTaskIds = @($Include)
    }
    elseif ($Profile -ne 'Interactive') {
        $selectedTaskIds = @($tasks | Where-Object { $_.Profiles -contains $Profile } | ForEach-Object { $_.Id })
    }
    else {
        if ($NonInteractive) {
            throw 'Use -Profile, -Config, or -Include with -NonInteractive.'
        }

        $menuItems = foreach ($task in $tasks) {
            $configured = $false
            try {
                $configured = [bool](& $task.Detect $context)
            }
            catch {
                $configured = $false
            }

            [pscustomobject]@{
                Id       = $task.Id
                Label    = "$($task.Category): $($task.Name)"
                Selected = [bool]$task.Default
                Status   = if ($configured) { 'configured' } else { '' }
            }
        }

        $selectedTaskIds = Show-MultiSelectMenu -Title 'Select the components to install and configure' -Items $menuItems
    }

    if ($null -ne $requestedPlan -and $null -ne $requestedPlan.options) {
        if (-not $PSBoundParameters.ContainsKey('GitName')) { $context.Options.GitName = $requestedPlan.options.GitName }
        if (-not $PSBoundParameters.ContainsKey('GitEmail')) { $context.Options.GitEmail = $requestedPlan.options.GitEmail }
        if (-not $PSBoundParameters.ContainsKey('WslDistribution') -and -not [string]::IsNullOrWhiteSpace($requestedPlan.options.WslDistribution)) {
            $context.Options.WslDistribution = $requestedPlan.options.WslDistribution
        }
        if (-not $PSBoundParameters.ContainsKey('WslWebDownload') -and $null -ne $requestedPlan.options.WslWebDownload) {
            $context.Options.WslWebDownload = [bool]$requestedPlan.options.WslWebDownload
        }
    }

    $selectedTaskIds = @($selectedTaskIds | Where-Object { $_ -notin $Exclude } | Select-Object -Unique)
    if ($selectedTaskIds.Count -eq 0) {
        Write-SetupMessage -Message 'No components were selected.' -Level Warning
        return
    }

    $knownTaskIds = @($tasks | ForEach-Object { $_.Id })
    $unknownTaskIds = @($selectedTaskIds | Where-Object { $_ -notin $knownTaskIds })
    if ($unknownTaskIds.Count -gt 0) {
        throw "Unknown task IDs: $($unknownTaskIds -join ', ')"
    }

    $requiresGitIdentity = @($selectedTaskIds | Where-Object {
        $_ -in @('git.windows-config', 'git.wsl-config', 'ssh.windows-key', 'ssh.github-upload')
    }).Count -gt 0
    if ($requiresGitIdentity) {
        if ([string]::IsNullOrWhiteSpace($context.Options.GitName)) {
            $context.Options.GitName = Get-GitConfigValue -Key 'user.name'
        }
        if ([string]::IsNullOrWhiteSpace($context.Options.GitEmail)) {
            $context.Options.GitEmail = Get-GitConfigValue -Key 'user.email'
        }

        $canPrompt = -not $NonInteractive -and -not [Console]::IsInputRedirected
        if ($canPrompt) {
            $context.Options.GitName = Read-RequiredValue -Prompt 'Git user name' -DefaultValue $context.Options.GitName
            $context.Options.GitEmail = Read-RequiredValue -Prompt 'Git email' -DefaultValue $context.Options.GitEmail
        }
        elseif ([string]::IsNullOrWhiteSpace($context.Options.GitName) -or [string]::IsNullOrWhiteSpace($context.Options.GitEmail)) {
            throw 'Git identity is required. Provide -GitName and -GitEmail.'
        }
    }

    $requiresWsl = @($selectedTaskIds | Where-Object { $_ -like 'wsl.*' -or $_ -like 'git.wsl-*' }).Count -gt 0
    if ($requiresWsl -and -not $NonInteractive -and -not $Resume -and $null -eq $requestedPlan -and -not [Console]::IsInputRedirected) {
        $context.Options.WslDistribution = Read-RequiredValue -Prompt 'WSL distribution' -DefaultValue $context.Options.WslDistribution
    }

    if ($requiresWsl -and -not (Test-WslDistributionSupported -Distribution $context.Options.WslDistribution)) {
        $supported = Get-SupportedWslDistributions
        throw "Unsupported WSL distribution '$($context.Options.WslDistribution)'. Supported distributions: $($supported -join ', ')."
    }

    if ($NonInteractive) {
        $taskMap = @{}
        foreach ($task in $tasks) { $taskMap[$task.Id] = $task }
        $orderedTaskIds = Resolve-TaskOrder -Tasks $tasks -SelectedTaskIds $selectedTaskIds
        foreach ($interactiveTaskId in @('github.authenticate', 'ssh.windows-key', 'wsl.initialize')) {
            if ($orderedTaskIds -notcontains $interactiveTaskId) { continue }

            $configured = $false
            try {
                $configured = [bool](& $taskMap[$interactiveTaskId].Detect $context)
            }
            catch {
                $configured = $false
            }

            if (-not $configured) {
                throw "Task '$interactiveTaskId' requires interactive input and cannot run with -NonInteractive. Configure it interactively, then resume."
            }
        }
    }

    $plan = [pscustomobject]@{
        schemaVersion = 1
        createdAt     = (Get-Date).ToUniversalTime().ToString('o')
        profile       = $Profile
        selectedTasks = $selectedTaskIds
        options       = $context.Options
    }
    Write-JsonFileAtomic -Value $plan -Path $paths.PlanPath

    Write-SetupMessage -Message "Selected tasks: $($selectedTaskIds.Count)" -Level Info
    if ($DryRun) { Write-SetupMessage -Message 'Dry-run mode is enabled.' -Level Muted }
    if ($Check) { Write-SetupMessage -Message 'Check mode is enabled.' -Level Muted }

    Invoke-SetupPlan -Tasks $tasks -SelectedTaskIds $selectedTaskIds -Context $context
    Write-SetupMessage -Message 'Environment setup finished.' -Level Success
}
finally {
    Exit-EnvSetupLock -Paths $paths
}
