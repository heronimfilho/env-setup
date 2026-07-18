#requires -version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Interactive', 'Core', 'Backend', 'Full')]
    [string]$Profile = 'Interactive',
    [string[]]$Include = @(),
    [string[]]$Exclude = @(),
    [switch]$Resume,
    [switch]$Check,
    [switch]$DryRun,
    [switch]$Repair,
    [switch]$NonInteractive,
    [string]$GitName,
    [string]$GitEmail,
    [string]$WslDistribution = 'Ubuntu'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Windows.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.Git.ps1')
. (Join-Path $PSScriptRoot 'src/EnvSetup.VSCode.ps1')

$paths = Initialize-EnvSetupStorage
$state = Read-JsonFile -Path $paths.StatePath -DefaultValue (New-EnvSetupState)
$tasks = @(
    Get-WindowsPackageTasks
    Get-GitTasks
    Get-VSCodeTasks
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
    }
}

if (-not (Test-CommandAvailable -Name 'winget.exe')) {
    throw 'WinGet is required. Install or update App Installer from Microsoft Store and run setup again.'
}

$selectedTaskIds = @()
$existingPlan = Read-JsonFile -Path $paths.PlanPath

if ($Resume) {
    if ($null -eq $existingPlan) {
        throw 'No saved setup plan was found.'
    }

    $selectedTaskIds = @($existingPlan.selectedTasks)
    if ($null -ne $existingPlan.options) {
        if ([string]::IsNullOrWhiteSpace($context.Options.GitName)) { $context.Options.GitName = $existingPlan.options.GitName }
        if ([string]::IsNullOrWhiteSpace($context.Options.GitEmail)) { $context.Options.GitEmail = $existingPlan.options.GitEmail }
        if ([string]::IsNullOrWhiteSpace($context.Options.WslDistribution)) { $context.Options.WslDistribution = $existingPlan.options.WslDistribution }
    }
}
elseif ($Include.Count -gt 0) {
    $selectedTaskIds = @($Include)
}
elseif ($Profile -ne 'Interactive') {
    $selectedTaskIds = @($tasks | Where-Object { $_.Profiles -contains $Profile } | ForEach-Object { $_.Id })
}
else {
    if ($NonInteractive) {
        throw 'Use -Profile or -Include with -NonInteractive.'
    }

    $menuItems = foreach ($task in $tasks) {
        $configured = [bool](& $task.Detect $context)
        [pscustomobject]@{
            Id       = $task.Id
            Label    = "$($task.Category): $($task.Name)"
            Selected = [bool]$task.Default
            Status   = if ($configured) { 'configured' } else { '' }
        }
    }

    $selectedTaskIds = Show-MultiSelectMenu -Title 'Select the components to install and configure' -Items $menuItems
}

$selectedTaskIds = @($selectedTaskIds | Where-Object { $_ -notin $Exclude } | Select-Object -Unique)
if ($selectedTaskIds.Count -eq 0) {
    Write-SetupMessage -Message 'No components were selected.' -Level Warning
    exit 0
}

$knownTaskIds = @($tasks | ForEach-Object { $_.Id })
$unknownTaskIds = @($selectedTaskIds | Where-Object { $_ -notin $knownTaskIds })
if ($unknownTaskIds.Count -gt 0) {
    throw "Unknown task IDs: $($unknownTaskIds -join ', ')"
}

$requiresGitIdentity = @($selectedTaskIds | Where-Object { $_ -in @('git.windows-config', 'ssh.windows-key', 'ssh.github-upload') }).Count -gt 0
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
