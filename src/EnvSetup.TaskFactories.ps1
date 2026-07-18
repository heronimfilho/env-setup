Set-StrictMode -Version Latest

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
        Detect        = [scriptblock]::Create("param(`$Context) Test-VSCodeExtensionGroup -Context `$Context -Group $groupLiteral")
        Apply         = [scriptblock]::Create("param(`$Context) Install-VSCodeExtensionGroup -Context `$Context -Group $groupLiteral")
        Verify        = [scriptblock]::Create("param(`$Context) Test-VSCodeExtensionGroup -Context `$Context -Group $groupLiteral")
    }
}
