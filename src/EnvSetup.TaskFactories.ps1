Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'EnvSetup.Progress.ps1')

function ConvertTo-EnvSetupSingleQuotedLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function New-WingetTask {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$PackageId,
        [bool]$Default = $false,
        [string[]]$Profiles = @()
    )

    $packageLiteral = ConvertTo-EnvSetupSingleQuotedLiteral -Value $PackageId
    return [pscustomobject]@{
        Id            = $Id
        Name          = $Name
        Category      = $Category
        Default       = $Default
        Profiles      = $Profiles
        RequiresAdmin = $false
        Dependencies  = @()
        DetectMessage = "Checking WinGet package state for $Name ($PackageId). WinGet source initialization can take a while on the first query..."
        ApplyMessage  = "Installing $Name with WinGet ($PackageId)..."
        VerifyMessage = "Verifying the WinGet installation for $Name ($PackageId)..."
        Detect        = [scriptblock]::Create("param(`$Context) Test-WingetPackageInstalled -PackageId $packageLiteral")
        Apply         = [scriptblock]::Create("param(`$Context) Install-WingetPackage -PackageId $packageLiteral")
        Verify        = [scriptblock]::Create("param(`$Context) Test-WingetPackageInstalled -PackageId $packageLiteral")
    }
}

function New-VSCodeExtensionTask {
    param(
        [string]$Id,
        [string]$Name,
        [string]$Group,
        [bool]$Default = $false,
        [string[]]$Profiles = @()
    )

    $groupLiteral = ConvertTo-EnvSetupSingleQuotedLiteral -Value $Group
    return [pscustomobject]@{
        Id            = $Id
        Name          = $Name
        Category      = 'Visual Studio Code'
        Default       = $Default
        Profiles      = $Profiles
        RequiresAdmin = $false
        Dependencies  = @('windows.vscode')
        DetectMessage = "Checking the installed Visual Studio Code extensions for the '$Group' group..."
        ApplyMessage  = "Installing missing Visual Studio Code extensions for the '$Group' group..."
        VerifyMessage = "Verifying the Visual Studio Code extensions for the '$Group' group..."
        Detect        = [scriptblock]::Create("param(`$Context) Test-VSCodeExtensionGroup -Context `$Context -Group $groupLiteral")
        Apply         = [scriptblock]::Create("param(`$Context) Install-VSCodeExtensionGroup -Context `$Context -Group $groupLiteral")
        Verify        = [scriptblock]::Create("param(`$Context) Test-VSCodeExtensionGroup -Context `$Context -Group $groupLiteral")
    }
}
