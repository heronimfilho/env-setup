Set-StrictMode -Version Latest

function Update-ProcessEnvironmentPath {
    $pathValues = @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User'),
        $env:Path
    )

    $entries = @(
        ($pathValues -join ';') -split ';' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
    $env:Path = $entries -join ';'
}

function Test-WingetPackageInstalled {
    param([Parameter(Mandatory = $true)][string]$PackageId)

    if (-not (Test-CommandAvailable -Name 'winget.exe')) {
        return $false
    }

    $result = Invoke-NativeCommand -FilePath 'winget.exe' -ArgumentList @(
        'list', '--id', $PackageId, '--exact', '--accept-source-agreements', '--disable-interactivity'
    ) -AllowFailure -Quiet

    return $result.Text -match [regex]::Escape($PackageId)
}

function Install-WingetPackage {
    param([Parameter(Mandatory = $true)][string]$PackageId)

    Invoke-NativeCommand -FilePath 'winget.exe' -ArgumentList @(
        'install', '--id', $PackageId, '--exact', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    ) | Out-Null
    Update-ProcessEnvironmentPath
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

    $package = $PackageId
    return [pscustomobject]@{
        Id            = $Id
        Name          = $Name
        Category      = $Category
        Default       = $Default
        Profiles      = $Profiles
        RequiresAdmin = $false
        Dependencies  = @()
        Detect        = { param($Context) Test-WingetPackageInstalled -PackageId $package }.GetNewClosure()
        Apply         = { param($Context) Install-WingetPackage -PackageId $package }.GetNewClosure()
        Verify        = { param($Context) Test-WingetPackageInstalled -PackageId $package }.GetNewClosure()
    }
}

function Get-WindowsPackageTasks {
    return @(
        New-WingetTask -Id 'windows.powershell' -Name 'PowerShell 7' -Category 'Core' -PackageId 'Microsoft.PowerShell' -Default $true -Profiles @('Core', 'Backend', 'Full')
        New-WingetTask -Id 'windows.terminal' -Name 'Windows Terminal' -Category 'Core' -PackageId 'Microsoft.WindowsTerminal' -Default $true -Profiles @('Core', 'Backend', 'Full')
        New-WingetTask -Id 'windows.git' -Name 'Git for Windows' -Category 'Core' -PackageId 'Git.Git' -Default $true -Profiles @('Core', 'Backend', 'Full')
        New-WingetTask -Id 'windows.github-cli' -Name 'GitHub CLI' -Category 'Core' -PackageId 'GitHub.cli' -Default $true -Profiles @('Core', 'Backend', 'Full')
        New-WingetTask -Id 'windows.vscode' -Name 'Visual Studio Code' -Category 'Core' -PackageId 'Microsoft.VisualStudioCode' -Default $true -Profiles @('Core', 'Backend', 'Full')
        New-WingetTask -Id 'windows.7zip' -Name '7-Zip' -Category 'Core' -PackageId '7zip.7zip' -Default $true -Profiles @('Core', 'Backend', 'Full')
        New-WingetTask -Id 'windows.powertoys' -Name 'PowerToys' -Category 'Optional tools' -PackageId 'Microsoft.PowerToys' -Profiles @('Full')
        New-WingetTask -Id 'windows.docker' -Name 'Docker Desktop' -Category 'Optional tools' -PackageId 'Docker.DockerDesktop' -Profiles @('Backend', 'Full')
        New-WingetTask -Id 'windows.dbeaver' -Name 'DBeaver' -Category 'Optional tools' -PackageId 'dbeaver.dbeaver' -Profiles @('Backend', 'Full')
        New-WingetTask -Id 'windows.bruno' -Name 'Bruno' -Category 'Optional tools' -PackageId 'Bruno.Bruno' -Profiles @('Backend', 'Full')
        New-WingetTask -Id 'windows.postman' -Name 'Postman' -Category 'Optional tools' -PackageId 'Postman.Postman' -Profiles @('Full')
        New-WingetTask -Id 'windows.dotnet' -Name '.NET SDK 10' -Category 'Development stacks' -PackageId 'Microsoft.DotNet.SDK.10' -Profiles @('Backend', 'Full')
        New-WingetTask -Id 'windows.aws-cli' -Name 'AWS CLI' -Category 'Cloud and infrastructure' -PackageId 'Amazon.AWSCLI' -Profiles @('Backend', 'Full')
        New-WingetTask -Id 'windows.terraform' -Name 'Terraform' -Category 'Cloud and infrastructure' -PackageId 'Hashicorp.Terraform' -Profiles @('Full')
        New-WingetTask -Id 'windows.kubectl' -Name 'kubectl' -Category 'Cloud and infrastructure' -PackageId 'Kubernetes.kubectl' -Profiles @('Full')
        New-WingetTask -Id 'windows.helm' -Name 'Helm' -Category 'Cloud and infrastructure' -PackageId 'Helm.Helm' -Profiles @('Full')
    )
}
