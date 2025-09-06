# WSL Installer
# Installs WSL2 with specified Linux distribution

[CmdletBinding()]
param(
    [ValidateSet("Ubuntu", "Ubuntu-22.04", "Ubuntu-20.04", "Debian", "kali-linux")]
    [string]$Distribution = "Ubuntu"
)

function Write-Status($Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Success($Message) { Write-Host $Message -ForegroundColor Green }
function Write-Error($Message) { Write-Host $Message -ForegroundColor Red }

# Check administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Administrator privileges required. Run PowerShell as Administrator."
    exit 1
}

# Check Windows version
$version = [System.Environment]::OSVersion.Version
if ($version.Major -lt 10 -or ($version.Major -eq 10 -and $version.Build -lt 19041)) {
    Write-Error "Windows 10 version 2004 (build 19041) or higher required."
    exit 1
}

Write-Status "Installing WSL2 with $Distribution..."

try {
    # Enable WSL features
    $features = @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")
    foreach ($feature in $features) {
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature).State
        if ($state -ne "Enabled") {
            Write-Status "Enabling $feature..."
            Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null
        }
    }

    # Install WSL2 kernel update
    $kernelUrl = "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi"
    $kernelPath = "$env:TEMP\wsl_update_x64.msi"
    
    if (-not (Test-Path $kernelPath)) {
        Write-Status "Downloading WSL2 kernel update..."
        Invoke-WebRequest -Uri $kernelUrl -OutFile $kernelPath -UseBasicParsing
    }
    
    Start-Process msiexec.exe -Wait -ArgumentList "/i $kernelPath /quiet" -WindowStyle Hidden

    # Set WSL2 as default
    wsl --set-default-version 2 2>$null

    # Install distribution
    Write-Status "Installing $Distribution..."
    wsl --install -d $Distribution --no-launch

    # Create basic WSL configuration
    $wslConfig = @"
[wsl2]
memory=4GB
processors=2
"@
    $wslConfig | Out-File -FilePath "$env:USERPROFILE\.wslconfig" -Encoding UTF8 -Force

    Write-Success "WSL2 installation completed."
    Write-Host "Launch '$Distribution' from Start Menu to complete setup." -ForegroundColor Yellow
}
catch {
    Write-Error "Installation failed: $($_.Exception.Message)"
    exit 1
}