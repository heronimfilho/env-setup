#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Git.ps1')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-git-tests-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$previousGlobalConfig = $env:GIT_CONFIG_GLOBAL
$env:GIT_CONFIG_GLOBAL = Join-Path $tempRoot '.gitconfig'

try {
    $paths = Initialize-EnvSetupStorage -RootPath $tempRoot
    $context = [pscustomobject]@{
        Paths = $paths
        Options = [pscustomobject]@{
            GitName = 'Test Developer'
            GitEmail = 'developer@example.com'
        }
    }

    Set-WindowsGitConfiguration -Context $context
    if (-not (Test-WindowsGitConfiguration -Context $context)) {
        throw 'Git configuration validation failed.'
    }

    if ((Get-GitConfigValue -Key 'user.name') -ne 'Test Developer') {
        throw 'Git user name was not configured.'
    }
    if ((Get-GitConfigValue -Key 'pull.ff') -ne 'only') {
        throw 'Git pull strategy was not configured.'
    }

    $gitTask = @(Get-GitTasks) | Where-Object { $_.Id -eq 'git.windows-config' } | Select-Object -First 1
    if ($gitTask.Dependencies -notcontains 'windows.vscode') {
        throw 'Git for Windows configuration must depend on Visual Studio Code.'
    }

    Write-Host 'Git tests passed.'
}
finally {
    $env:GIT_CONFIG_GLOBAL = $previousGlobalConfig
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
