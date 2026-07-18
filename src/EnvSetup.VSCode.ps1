Set-StrictMode -Version Latest

function ConvertFrom-Jsonc {
    param([Parameter(Mandatory = $true)][string]$Content)

    $withoutComments = [System.Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    $lineComment = $false
    $blockComment = $false

    for ($index = 0; $index -lt $Content.Length; $index++) {
        $character = $Content[$index]
        $next = if ($index + 1 -lt $Content.Length) { $Content[$index + 1] } else { [char]0 }

        if ($lineComment) {
            if ($character -eq "`n") {
                $lineComment = $false
                [void]$withoutComments.Append($character)
            }
            continue
        }

        if ($blockComment) {
            if ($character -eq '*' -and $next -eq '/') {
                $blockComment = $false
                $index++
            }
            elseif ($character -eq "`n") {
                [void]$withoutComments.Append($character)
            }
            continue
        }

        if ($inString) {
            [void]$withoutComments.Append($character)
            if ($escaped) {
                $escaped = $false
            }
            elseif ($character -eq '\') {
                $escaped = $true
            }
            elseif ($character -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($character -eq '"') {
            $inString = $true
            [void]$withoutComments.Append($character)
        }
        elseif ($character -eq '/' -and $next -eq '/') {
            $lineComment = $true
            $index++
        }
        elseif ($character -eq '/' -and $next -eq '*') {
            $blockComment = $true
            $index++
        }
        else {
            [void]$withoutComments.Append($character)
        }
    }

    $clean = $withoutComments.ToString()
    $withoutTrailingCommas = [System.Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false

    for ($index = 0; $index -lt $clean.Length; $index++) {
        $character = $clean[$index]

        if ($inString) {
            [void]$withoutTrailingCommas.Append($character)
            if ($escaped) {
                $escaped = $false
            }
            elseif ($character -eq '\') {
                $escaped = $true
            }
            elseif ($character -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($character -eq '"') {
            $inString = $true
            [void]$withoutTrailingCommas.Append($character)
            continue
        }

        if ($character -eq ',') {
            $lookAhead = $index + 1
            while ($lookAhead -lt $clean.Length -and [char]::IsWhiteSpace($clean[$lookAhead])) {
                $lookAhead++
            }
            if ($lookAhead -lt $clean.Length -and $clean[$lookAhead] -in @('}', ']')) {
                continue
            }
        }

        [void]$withoutTrailingCommas.Append($character)
    }

    return $withoutTrailingCommas.ToString() | ConvertFrom-Json
}

function Get-CodeCommand {
    $command = Get-Command 'code.cmd' -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'),
        (Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd')
    )

    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\bin\code.cmd'
    }

    return $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

function Invoke-CodeCommand {
    param(
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [switch]$AllowFailure,
        [switch]$Quiet
    )

    $code = Get-CodeCommand
    if ([string]::IsNullOrWhiteSpace($code)) {
        throw 'The Visual Studio Code command line was not found. Restart the terminal after installation and resume setup.'
    }

    $output = @(& $code @ArgumentList 2>&1)
    $exitCode = $LASTEXITCODE
    if (-not $Quiet) { $output | ForEach-Object { Write-Host $_ } }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "Visual Studio Code CLI exited with code $exitCode.`n$($output -join [Environment]::NewLine)"
    }

    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output; Text = ($output -join [Environment]::NewLine) }
}

function Get-VSCodeUserSettingsPath {
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        throw 'APPDATA is not available.'
    }
    return Join-Path $env:APPDATA 'Code\User\settings.json'
}

function Get-DesiredVSCodeSettings {
    param([Parameter(Mandatory = $true)]$Context)
    $path = Join-Path $Context.ProjectRoot 'vscode.settings.json'
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Test-IsObjectNode {
    param($Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [string] -or $Value -is [System.Array]) { return $false }
    return $Value -is [pscustomobject] -or $Value -is [System.Collections.IDictionary]
}

function Set-ObjectProperties {
    param(
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)]$Source
    )

    foreach ($property in $Source.PSObject.Properties) {
        $targetProperty = $Target.PSObject.Properties[$property.Name]
        if ($null -ne $targetProperty -and
            (Test-IsObjectNode -Value $targetProperty.Value) -and
            (Test-IsObjectNode -Value $property.Value)) {
            Set-ObjectProperties -Target $targetProperty.Value -Source $property.Value | Out-Null
            continue
        }

        $Target | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
    }
    return $Target
}

function Test-ObjectContainsProperties {
    param(
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)]$Expected
    )

    foreach ($property in $Expected.PSObject.Properties) {
        $actualProperty = $Actual.PSObject.Properties[$property.Name]
        if ($null -eq $actualProperty) { return $false }

        if ((Test-IsObjectNode -Value $actualProperty.Value) -and
            (Test-IsObjectNode -Value $property.Value)) {
            if (-not (Test-ObjectContainsProperties -Actual $actualProperty.Value -Expected $property.Value)) {
                return $false
            }
            continue
        }

        $actualJson = $actualProperty.Value | ConvertTo-Json -Depth 20 -Compress
        $expectedJson = $property.Value | ConvertTo-Json -Depth 20 -Compress
        if ($actualJson -ne $expectedJson) { return $false }
    }
    return $true
}

function Test-VSCodeSettings {
    param([Parameter(Mandatory = $true)]$Context)

    $path = Get-VSCodeUserSettingsPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }

    try {
        $actual = ConvertFrom-Jsonc -Content (Get-Content -LiteralPath $path -Raw)
        $expected = Get-DesiredVSCodeSettings -Context $Context
        return Test-ObjectContainsProperties -Actual $actual -Expected $expected
    }
    catch {
        return $false
    }
}

function Set-VSCodeSettings {
    param([Parameter(Mandatory = $true)]$Context)

    $path = Get-VSCodeUserSettingsPath
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $settings = [pscustomobject]@{}
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $settings = ConvertFrom-Jsonc -Content (Get-Content -LiteralPath $path -Raw)
        $backup = Join-Path (Join-Path $Context.Paths.RootPath 'backups') ("vscode-settings-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Copy-Item -LiteralPath $path -Destination $backup -Force
    }

    $settings = Set-ObjectProperties -Target $settings -Source (Get-DesiredVSCodeSettings -Context $Context)
    [System.IO.File]::WriteAllText($path, ($settings | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
}

function Get-VSCodeExtensionGroup {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Group
    )

    $manifestPath = Join-Path $Context.ProjectRoot 'config/vscode.extensions.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $property = $manifest.PSObject.Properties[$Group]
    if ($null -eq $property) { throw "Unknown VS Code extension group: $Group" }
    return $property.Value
}

function Get-InstalledVSCodeExtensions {
    param([string]$Profile)

    $arguments = @('--list-extensions')
    if (-not [string]::IsNullOrWhiteSpace($Profile)) {
        $arguments += @('--profile', $Profile)
    }
    $result = Invoke-CodeCommand -ArgumentList $arguments -Quiet
    return @($result.Output | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
}

function Test-VSCodeExtensionGroup {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Group
    )

    $definition = Get-VSCodeExtensionGroup -Context $Context -Group $Group
    $installed = Get-InstalledVSCodeExtensions -Profile $definition.profile
    foreach ($extension in @($definition.extensions)) {
        if ($installed -notcontains $extension.ToLowerInvariant()) { return $false }
    }
    return $true
}

function Install-VSCodeExtensionGroup {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Group
    )

    $definition = Get-VSCodeExtensionGroup -Context $Context -Group $Group
    $installed = Get-InstalledVSCodeExtensions -Profile $definition.profile
    foreach ($extension in @($definition.extensions)) {
        if ($installed -contains $extension.ToLowerInvariant()) { continue }
        $arguments = @('--install-extension', $extension, '--force')
        if (-not [string]::IsNullOrWhiteSpace($definition.profile)) {
            $arguments += @('--profile', $definition.profile)
        }
        Invoke-CodeCommand -ArgumentList $arguments | Out-Null
    }
}

function New-VSCodeExtensionTask {
    param(
        [string]$Id, [string]$Name, [string]$Group, [bool]$Default = $false, [string[]]$Profiles = @()
    )
    $groupName = $Group
    return [pscustomobject]@{
        Id = $Id; Name = $Name; Category = 'Visual Studio Code'; Default = $Default; Profiles = $Profiles
        RequiresAdmin = $false; Dependencies = @('windows.vscode')
        Detect = { param($Context) Test-VSCodeExtensionGroup -Context $Context -Group $groupName }.GetNewClosure()
        Apply = { param($Context) Install-VSCodeExtensionGroup -Context $Context -Group $groupName }.GetNewClosure()
        Verify = { param($Context) Test-VSCodeExtensionGroup -Context $Context -Group $groupName }.GetNewClosure()
    }
}

function Get-VSCodeTasks {
    return @(
        [pscustomobject]@{
            Id = 'vscode.settings'; Name = 'Merge Visual Studio Code settings'; Category = 'Visual Studio Code'; Default = $true
            Profiles = @('Core', 'Backend', 'Full'); RequiresAdmin = $false; Dependencies = @('windows.vscode')
            Detect = { param($Context) Test-VSCodeSettings -Context $Context }
            Apply = { param($Context) Set-VSCodeSettings -Context $Context }
            Verify = { param($Context) Test-VSCodeSettings -Context $Context }
        }
        New-VSCodeExtensionTask -Id 'vscode.extensions-base' -Name 'Install base extensions' -Group 'base' -Default $true -Profiles @('Core', 'Backend', 'Full')
        New-VSCodeExtensionTask -Id 'vscode.extensions-node' -Name 'Create the Node.js extension profile' -Group 'node' -Profiles @('Backend', 'Full')
        New-VSCodeExtensionTask -Id 'vscode.extensions-dotnet' -Name 'Create the .NET extension profile' -Group 'dotnet' -Profiles @('Backend', 'Full')
        New-VSCodeExtensionTask -Id 'vscode.extensions-delphi' -Name 'Create the Delphi extension profile' -Group 'delphi' -Profiles @('Full')
        New-VSCodeExtensionTask -Id 'vscode.extensions-devops' -Name 'Create the DevOps extension profile' -Group 'devops' -Profiles @('Full')
    )
}
