Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'EnvSetup.TaskFactories.ps1')

function Test-RegistryDwordValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        return [int](Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop) -eq $Value
    }
    catch { return $false }
}

function Set-RegistryDwordValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Test-WindowsSandboxEnabled {
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM' -ErrorAction Stop
        return $feature.State -eq 'Enabled'
    }
    catch { return $false }
}

function Enable-WindowsSandboxFeature {
    $result = Enable-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM' -All -NoRestart -ErrorAction Stop
    if ($result.RestartNeeded) {
        Write-SetupMessage -Message 'Windows Sandbox was enabled. Restart Windows before using it.' -Level Warning
    }
}

function Get-WindowsSettingsTasks {
    return @(
        [pscustomobject]@{
            Id = 'windows.show-extensions'; Name = 'Show file name extensions'; Category = 'Windows settings'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $false; Dependencies = @()
            Detect = { param($Context) Test-RegistryDwordValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 }
            Apply = { param($Context) Set-RegistryDwordValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 }
            Verify = { param($Context) Test-RegistryDwordValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 }
        }
        [pscustomobject]@{
            Id = 'windows.show-hidden'; Name = 'Show hidden files'; Category = 'Windows settings'; Default = $false
            Profiles = @('Full'); RequiresAdmin = $false; Dependencies = @()
            Detect = { param($Context) Test-RegistryDwordValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Hidden' -Value 1 }
            Apply = { param($Context) Set-RegistryDwordValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Hidden' -Value 1 }
            Verify = { param($Context) Test-RegistryDwordValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Hidden' -Value 1 }
        }
        [pscustomobject]@{
            Id = 'windows.long-paths'; Name = 'Enable long Win32 paths'; Category = 'Windows settings'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $true; Dependencies = @()
            Detect = { param($Context) Test-RegistryDwordValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 }
            Apply = { param($Context) Set-RegistryDwordValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 }
            Verify = { param($Context) Test-RegistryDwordValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 }
        }
        [pscustomobject]@{
            Id = 'windows.developer-mode'; Name = 'Enable Windows Developer Mode'; Category = 'Windows settings'; Default = $false
            Profiles = @('Full'); RequiresAdmin = $true; Dependencies = @()
            Detect = { param($Context) Test-RegistryDwordValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 }
            Apply = { param($Context) Set-RegistryDwordValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 }
            Verify = { param($Context) Test-RegistryDwordValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 }
        }
        [pscustomobject]@{
            Id = 'windows.sandbox'; Name = 'Enable Windows Sandbox'; Category = 'Windows settings'; Default = $false
            Profiles = @('Full'); RequiresAdmin = $true; Dependencies = @()
            Detect = { param($Context) Test-WindowsSandboxEnabled }
            Apply = { param($Context) Enable-WindowsSandboxFeature }
            Verify = { param($Context) Test-WindowsSandboxEnabled }
        }
    )
}
