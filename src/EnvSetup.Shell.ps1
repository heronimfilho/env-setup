Set-StrictMode -Version Latest

function Get-NormalizedText {
    param([AllowEmptyString()][string]$Content)
    if ($null -eq $Content) { return '' }
    return (($Content -replace "`r`n", "`n") -replace "`r", "`n").Trim()
}

function Get-ManagedTextBlockContent {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$StartMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker
    )

    $startMatches = [regex]::Matches($Content, '(?m)^' + [regex]::Escape($StartMarker) + '\s*$')
    $endMatches = [regex]::Matches($Content, '(?m)^' + [regex]::Escape($EndMarker) + '\s*$')
    if ($startMatches.Count -ne $endMatches.Count -or $startMatches.Count -gt 1) {
        throw "The managed block markers are incomplete or duplicated: $StartMarker"
    }
    if ($startMatches.Count -eq 0) { return $null }

    $pattern = '(?ms)^' + [regex]::Escape($StartMarker) + '\s*\r?\n(.*?)^' + [regex]::Escape($EndMarker) + '\s*$'
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success) {
        throw "The managed block could not be parsed: $StartMarker"
    }
    return $match.Groups[1].Value
}

function Test-ManagedTextBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$StartMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker,
        [Parameter(Mandatory = $true)][string]$ExpectedContent
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $actual = Get-ManagedTextBlockContent -Content (Get-Content -LiteralPath $Path -Raw) -StartMarker $StartMarker -EndMarker $EndMarker
        if ($null -eq $actual) { return $false }
        return (Get-NormalizedText -Content $actual) -eq (Get-NormalizedText -Content $ExpectedContent)
    }
    catch { return $false }
}

function Set-ManagedTextBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$StartMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker,
        [Parameter(Mandatory = $true)][string]$Content,
        [string]$BackupDirectory
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $existing = if (Test-Path -LiteralPath $Path -PathType Leaf) { Get-Content -LiteralPath $Path -Raw } else { '' }
    [void](Get-ManagedTextBlockContent -Content $existing -StartMarker $StartMarker -EndMarker $EndMarker)

    if (-not [string]::IsNullOrWhiteSpace($existing) -and -not [string]::IsNullOrWhiteSpace($BackupDirectory)) {
        if (-not (Test-Path -LiteralPath $BackupDirectory)) {
            New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
        }
        $backupPath = Join-Path $BackupDirectory ("{0}-{1}-{2}.bak" -f (Split-Path -Leaf $Path), (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID)
        [System.IO.File]::WriteAllText($backupPath, $existing, [System.Text.UTF8Encoding]::new($false))
    }

    $pattern = '(?ms)^' + [regex]::Escape($StartMarker) + '.*?^' + [regex]::Escape($EndMarker) + '\s*'
    $cleaned = [regex]::Replace($existing, $pattern, '').TrimEnd()
    $newContent = if ([string]::IsNullOrWhiteSpace($cleaned)) {
        "$StartMarker`r`n$Content`r`n$EndMarker`r`n"
    }
    else {
        "$cleaned`r`n`r`n$StartMarker`r`n$Content`r`n$EndMarker`r`n"
    }

    $temporaryPath = "$Path.env-setup.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $newContent, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-PwshCommand {
    $command = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $candidate = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    return $null
}

function Get-PowerShellProfilePath {
    $pwsh = Get-PwshCommand
    if ([string]::IsNullOrWhiteSpace($pwsh)) { return $null }

    $path = (& $pwsh -NoLogo -NoProfile -Command '$PROFILE.CurrentUserAllHosts' | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($path)) { return $null }
    return $path
}

function Get-PowerShellProfileBlock {
    return @'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

if ($Host.Name -eq 'ConsoleHost' -and (Get-Module -ListAvailable -Name PSReadLine)) {
    Import-Module PSReadLine
    Set-PSReadLineOption -HistoryNoDuplicates
    try {
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -PredictionViewStyle ListView
    }
    catch {
        # Prediction features depend on the installed PSReadLine version and terminal capabilities.
    }
}

function New-DirectoryAndEnter {
    param([Parameter(Mandatory = $true)][string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location -LiteralPath $Path
}

function Update-DevelopmentTools {
    winget upgrade --all --accept-package-agreements --accept-source-agreements
}

Set-Alias -Name mkcd -Value New-DirectoryAndEnter
'@
}

function Test-PowerShellProfileConfiguration {
    $path = Get-PowerShellProfilePath
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    return Test-ManagedTextBlock -Path $path `
        -StartMarker '# >>> env-setup powershell >>>' `
        -EndMarker '# <<< env-setup powershell <<<' `
        -ExpectedContent (Get-PowerShellProfileBlock)
}

function Set-PowerShellProfileConfiguration {
    param([Parameter(Mandatory = $true)]$Context)
    $path = Get-PowerShellProfilePath
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw 'PowerShell 7 was not found. Restart the terminal after installation and resume setup.'
    }

    Set-ManagedTextBlock -Path $path `
        -StartMarker '# >>> env-setup powershell >>>' `
        -EndMarker '# <<< env-setup powershell <<<' `
        -Content (Get-PowerShellProfileBlock) `
        -BackupDirectory (Join-Path $Context.Paths.RootPath 'backups')
}

function Get-WindowsTerminalFragmentPath {
    return Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\env-setup\settings.json'
}

function Get-WindowsTerminalFragment {
    return [pscustomobject]@{
        profiles = @(
            [pscustomobject]@{
                name = 'PowerShell 7 (env-setup)'
                commandline = 'pwsh.exe'
                startingDirectory = '%USERPROFILE%'
                colorScheme = 'Catppuccin Mocha'
                hidden = $false
            }
        )
        schemes = @(
            [pscustomobject]@{
                name = 'Catppuccin Mocha'
                background = '#1E1E2E'
                foreground = '#CDD6F4'
                cursorColor = '#F5E0DC'
                selectionBackground = '#585B70'
                black = '#45475A'
                red = '#F38BA8'
                green = '#A6E3A1'
                yellow = '#F9E2AF'
                blue = '#89B4FA'
                purple = '#F5C2E7'
                cyan = '#94E2D5'
                white = '#BAC2DE'
                brightBlack = '#585B70'
                brightRed = '#F38BA8'
                brightGreen = '#A6E3A1'
                brightYellow = '#F9E2AF'
                brightBlue = '#89B4FA'
                brightPurple = '#F5C2E7'
                brightCyan = '#94E2D5'
                brightWhite = '#A6ADC8'
            }
        )
    }
}

function ConvertTo-CanonicalJson {
    param([Parameter(Mandatory = $true)]$Value)
    return $Value | ConvertTo-Json -Depth 20 -Compress
}

function Test-WindowsTerminalFragment {
    $path = Get-WindowsTerminalFragmentPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    try {
        $actual = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        return (ConvertTo-CanonicalJson -Value $actual) -eq (ConvertTo-CanonicalJson -Value (Get-WindowsTerminalFragment))
    }
    catch { return $false }
}

function Set-WindowsTerminalFragment {
    $path = Get-WindowsTerminalFragmentPath
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($path, ((Get-WindowsTerminalFragment) | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
}

function Get-ShellTasks {
    return @(
        [pscustomobject]@{
            Id = 'powershell.profile'; Name = 'Configure the PowerShell 7 profile'; Category = 'Shell'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $false; Dependencies = @('windows.powershell')
            Detect = { param($Context) Test-PowerShellProfileConfiguration }
            Apply = { param($Context) Set-PowerShellProfileConfiguration -Context $Context }
            Verify = { param($Context) Test-PowerShellProfileConfiguration }
        }
        [pscustomobject]@{
            Id = 'terminal.fragment'; Name = 'Configure Windows Terminal'; Category = 'Shell'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $false; Dependencies = @('windows.terminal', 'windows.powershell')
            Detect = { param($Context) Test-WindowsTerminalFragment }
            Apply = { param($Context) Set-WindowsTerminalFragment }
            Verify = { param($Context) Test-WindowsTerminalFragment }
        }
    )
}
