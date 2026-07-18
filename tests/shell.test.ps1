#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Shell.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.WindowsSettings.ps1')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-shell-tests-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $profilePath = Join-Path $tempRoot 'profile.ps1'
    Set-Content -LiteralPath $profilePath -Value "Write-Host 'preserved'"

    Set-ManagedTextBlock -Path $profilePath `
        -StartMarker '# >>> env-setup test >>>' `
        -EndMarker '# <<< env-setup test <<<' `
        -Content "Write-Host 'managed'" `
        -BackupDirectory (Join-Path $tempRoot 'backups')
    Set-ManagedTextBlock -Path $profilePath `
        -StartMarker '# >>> env-setup test >>>' `
        -EndMarker '# <<< env-setup test <<<' `
        -Content "Write-Host 'managed'" `
        -BackupDirectory (Join-Path $tempRoot 'backups')

    $content = Get-Content -LiteralPath $profilePath -Raw
    if (($content | Select-String -Pattern '# >>> env-setup test >>>' -AllMatches).Matches.Count -ne 1) {
        throw 'The managed profile block was duplicated.'
    }
    if (-not $content.Contains("Write-Host 'preserved'")) {
        throw 'Existing profile content was not preserved.'
    }

    $fragment = Get-WindowsTerminalFragment
    if ($fragment.profiles[0].commandline -ne 'pwsh.exe') {
        throw 'The Windows Terminal profile does not use PowerShell 7.'
    }
    if (@($fragment.schemes[0].PSObject.Properties).Count -lt 20) {
        throw 'The Windows Terminal color scheme is incomplete.'
    }

    $settingTaskIds = @(Get-WindowsSettingsTasks | ForEach-Object { $_.Id })
    foreach ($taskId in @('windows.show-extensions', 'windows.long-paths', 'windows.developer-mode', 'windows.sandbox')) {
        if ($settingTaskIds -notcontains $taskId) {
            throw "Missing Windows settings task: $taskId"
        }
    }

    Write-Host 'Shell tests passed.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
