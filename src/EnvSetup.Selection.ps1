Set-StrictMode -Version Latest

function Get-ValidatedSavedSetupPlan {
    param($Plan)

    if ($null -eq $Plan) { return $null }

    try {
        Assert-SetupPlanSchema -Plan $Plan
        return $Plan
    }
    catch {
        Write-SetupMessage -Message "The saved setup plan is invalid and will be ignored: $($_.Exception.Message)" -Level Warning
        return $null
    }
}

function Get-InteractiveTaskMenuItems {
    param(
        [Parameter(Mandatory = $true)][object[]]$Tasks,
        [Parameter(Mandatory = $true)]$Context,
        $SavedPlan
    )

    $useSavedSelection = $null -ne $SavedPlan
    $savedTaskIds = if ($useSavedSelection) { @($SavedPlan.selectedTasks) } else { @() }

    return @(
        foreach ($task in $Tasks) {
            $configured = $false
            try {
                $configured = [bool](& $task.Detect $Context)
            }
            catch {
                $configured = $false
            }

            [pscustomobject]@{
                Id       = $task.Id
                Label    = "$($task.Category): $($task.Name)"
                Selected = if ($useSavedSelection) {
                    $savedTaskIds -contains $task.Id
                }
                else {
                    [bool]$task.Default
                }
                Status   = if ($configured) { 'configured' } else { '' }
            }
        }
    )
}

function Set-SetupOptionsFromPlan {
    param(
        [Parameter(Mandatory = $true)]$Context,
        $Plan,
        [string[]]$ExplicitOptionNames = @()
    )

    if ($null -eq $Plan) { return }

    $requestedOptions = Get-OptionalPropertyValue -Object $Plan -Name 'options'
    if ($null -eq $requestedOptions) { return }

    if ($ExplicitOptionNames -notcontains 'GitName') {
        $Context.Options.GitName = Get-OptionalPropertyValue -Object $requestedOptions -Name 'GitName' -DefaultValue $Context.Options.GitName
    }
    if ($ExplicitOptionNames -notcontains 'GitEmail') {
        $Context.Options.GitEmail = Get-OptionalPropertyValue -Object $requestedOptions -Name 'GitEmail' -DefaultValue $Context.Options.GitEmail
    }
    if ($ExplicitOptionNames -notcontains 'WslDistribution') {
        $requestedDistribution = Get-OptionalPropertyValue -Object $requestedOptions -Name 'WslDistribution'
        if (-not [string]::IsNullOrWhiteSpace([string]$requestedDistribution)) {
            $Context.Options.WslDistribution = [string]$requestedDistribution
        }
    }
    if ($ExplicitOptionNames -notcontains 'WslWebDownload') {
        $requestedWebDownload = Get-OptionalPropertyValue -Object $requestedOptions -Name 'WslWebDownload'
        if ($null -ne $requestedWebDownload) {
            $Context.Options.WslWebDownload = [bool]$requestedWebDownload
        }
    }
}
