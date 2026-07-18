#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.Shell.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.WindowsSettings.ps1')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("env-setup-shell-tests-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$previousLocalAppData = $env:LOCALAPPDATA

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
    if (-not (Test-ManagedTextBlock -Path $profilePath `
        -StartMarker '# >>> env-setup test >>>' `
        -EndMarker '# <<< env-setup test <<<' `
        -ExpectedContent "Write-Host 'managed'")) {
        throw 'The complete managed profile block was not detected.'
    }

    Set-Content -LiteralPath $profilePath -Value @'
# >>> env-setup test >>>
Write-Host 'incomplete'
'@
    $before = Get-Content -LiteralPath $profilePath -Raw
    $incompleteFailed = $false
    try {
        Set-ManagedTextBlock -Path $profilePath `
            -StartMarker '# >>> env-setup test >>>' `
            -EndMarker '# <<< env-setup test <<<' `
            -Content "Write-Host 'managed'"
    }
    catch {
        $incompleteFailed = $true
    }
    if (-not $incompleteFailed) {
        throw 'An incomplete managed profile block was accepted.'
    }
    if ((Get-Content -LiteralPath $profilePath -Raw) -ne $before) {
        throw 'An incomplete managed profile block modified the file.'
    }

    $env:LOCALAPPDATA = Join-Path $tempRoot 'local-app-data'
    Set-WindowsTerminalFragment
    if (-not (Test-WindowsTerminalFragment)) {
        throw 'The complete Windows Terminal fragment was not detected.'
    }

    $fragmentPath = Get-WindowsTerminalFragmentPath
    $fragment = Get-Content -LiteralPath $fragmentPath -Raw | ConvertFrom-Json
    $fragment.profiles[0].commandline = 'powershell.exe'
    [System.IO.File]::WriteAllText($fragmentPath, ($fragment | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
    if (Test-WindowsTerminalFragment) {
        throw 'A modified Windows Terminal command line was accepted.'
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
    $env:LOCALAPPDATA = $previousLocalAppData
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
