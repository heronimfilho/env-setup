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

function Get-JsoncSignificantIndex {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$Index,
        [int]$Limit = $Content.Length
    )

    while ($Index -lt $Limit) {
        if ([char]::IsWhiteSpace($Content[$Index])) {
            $Index++
            continue
        }

        if ($Content[$Index] -eq '/' -and $Index + 1 -lt $Limit) {
            if ($Content[$Index + 1] -eq '/') {
                $Index += 2
                while ($Index -lt $Limit -and $Content[$Index] -ne "`n") { $Index++ }
                continue
            }
            if ($Content[$Index + 1] -eq '*') {
                $Index += 2
                $closed = $false
                while ($Index + 1 -lt $Limit) {
                    if ($Content[$Index] -eq '*' -and $Content[$Index + 1] -eq '/') {
                        $Index += 2
                        $closed = $true
                        break
                    }
                    $Index++
                }
                if (-not $closed) { throw 'Unterminated JSONC block comment.' }
                continue
            }
        }

        return $Index
    }

    return $Index
}

function Get-JsoncStringEnd {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$StartIndex
    )

    if ($Content[$StartIndex] -ne '"') { throw 'Expected a JSON string.' }
    $escaped = $false
    for ($index = $StartIndex + 1; $index -lt $Content.Length; $index++) {
        $character = $Content[$index]
        if ($escaped) {
            $escaped = $false
        }
        elseif ($character -eq '\') {
            $escaped = $true
        }
        elseif ($character -eq '"') {
            return $index + 1
        }
    }
    throw 'Unterminated JSON string.'
}

function Get-JsoncCompositeEnd {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$StartIndex
    )

    $opening = $Content[$StartIndex]
    if ($opening -notin @('{', '[')) { throw 'Expected a JSON object or array.' }
    $stack = New-Object System.Collections.Generic.Stack[char]
    $stack.Push($(if ($opening -eq '{') { '}' } else { ']' }))
    $inString = $false
    $escaped = $false
    $lineComment = $false
    $blockComment = $false

    for ($index = $StartIndex + 1; $index -lt $Content.Length; $index++) {
        $character = $Content[$index]
        $next = if ($index + 1 -lt $Content.Length) { $Content[$index + 1] } else { [char]0 }

        if ($lineComment) {
            if ($character -eq "`n") { $lineComment = $false }
            continue
        }
        if ($blockComment) {
            if ($character -eq '*' -and $next -eq '/') {
                $blockComment = $false
                $index++
            }
            continue
        }
        if ($inString) {
            if ($escaped) { $escaped = $false }
            elseif ($character -eq '\') { $escaped = $true }
            elseif ($character -eq '"') { $inString = $false }
            continue
        }

        if ($character -eq '"') { $inString = $true; continue }
        if ($character -eq '/' -and $next -eq '/') { $lineComment = $true; $index++; continue }
        if ($character -eq '/' -and $next -eq '*') { $blockComment = $true; $index++; continue }
        if ($character -eq '{') { $stack.Push('}'); continue }
        if ($character -eq '[') { $stack.Push(']'); continue }
        if ($stack.Count -gt 0 -and $character -eq $stack.Peek()) {
            [void]$stack.Pop()
            if ($stack.Count -eq 0) { return $index + 1 }
        }
    }

    throw 'Unterminated JSON object or array.'
}

function Get-JsoncValueEnd {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$StartIndex,
        [int]$Limit = $Content.Length
    )

    $StartIndex = Get-JsoncSignificantIndex -Content $Content -Index $StartIndex -Limit $Limit
    if ($StartIndex -ge $Limit) { throw 'A JSON value is missing.' }
    $character = $Content[$StartIndex]
    if ($character -eq '"') { return Get-JsoncStringEnd -Content $Content -StartIndex $StartIndex }
    if ($character -in @('{', '[')) { return Get-JsoncCompositeEnd -Content $Content -StartIndex $StartIndex }

    $index = $StartIndex
    while ($index -lt $Limit) {
        $character = $Content[$index]
        if ([char]::IsWhiteSpace($character) -or $character -in @(',', '}', ']')) { break }
        if ($character -eq '/' -and $index + 1 -lt $Limit -and $Content[$index + 1] -in @('/', '*')) { break }
        $index++
    }
    if ($index -eq $StartIndex) { throw 'A JSON value is missing.' }
    return $index
}

function Get-JsoncObjectBounds {
    param([Parameter(Mandatory = $true)][string]$Content)

    $start = Get-JsoncSignificantIndex -Content $Content -Index 0
    if ($start -ge $Content.Length -or $Content[$start] -ne '{') {
        throw 'The JSONC root must be an object.'
    }
    $endExclusive = Get-JsoncCompositeEnd -Content $Content -StartIndex $start
    return [pscustomobject]@{
        Start = $start
        EndExclusive = $endExclusive
        CloseIndex = $endExclusive - 1
    }
}

function Get-JsoncObjectProperties {
    param([Parameter(Mandatory = $true)][string]$Content)

    $bounds = Get-JsoncObjectBounds -Content $Content
    $properties = New-Object System.Collections.Generic.List[object]
    $cursor = Get-JsoncSignificantIndex -Content $Content -Index ($bounds.Start + 1) -Limit $bounds.CloseIndex

    while ($cursor -lt $bounds.CloseIndex) {
        if ($Content[$cursor] -eq ',') {
            $cursor = Get-JsoncSignificantIndex -Content $Content -Index ($cursor + 1) -Limit $bounds.CloseIndex
            continue
        }
        if ($Content[$cursor] -ne '"') { throw 'Expected a JSON object property name.' }

        $keyStart = $cursor
        $keyEnd = Get-JsoncStringEnd -Content $Content -StartIndex $keyStart
        $name = $Content.Substring($keyStart, $keyEnd - $keyStart) | ConvertFrom-Json
        $cursor = Get-JsoncSignificantIndex -Content $Content -Index $keyEnd -Limit $bounds.CloseIndex
        if ($cursor -ge $bounds.CloseIndex -or $Content[$cursor] -ne ':') { throw "Missing colon after JSON property: $name" }

        $valueStart = Get-JsoncSignificantIndex -Content $Content -Index ($cursor + 1) -Limit $bounds.CloseIndex
        $valueEnd = Get-JsoncValueEnd -Content $Content -StartIndex $valueStart -Limit $bounds.CloseIndex
        $afterValue = Get-JsoncSignificantIndex -Content $Content -Index $valueEnd -Limit $bounds.CloseIndex
        $hasFollowingComma = $afterValue -lt $bounds.CloseIndex -and $Content[$afterValue] -eq ','

        $lineStart = $Content.LastIndexOf("`n", [Math]::Max(0, $keyStart - 1))
        if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart++ }
        $indentation = $Content.Substring($lineStart, $keyStart - $lineStart)
        if ($indentation -notmatch '^\s*$') { $indentation = '' }

        $properties.Add([pscustomobject]@{
            Name = [string]$name
            KeyStart = $keyStart
            ValueStart = $valueStart
            ValueEnd = $valueEnd
            ValueText = $Content.Substring($valueStart, $valueEnd - $valueStart)
            Indentation = $indentation
            HasFollowingComma = $hasFollowingComma
        })

        $cursor = if ($hasFollowingComma) { $afterValue + 1 } else { $afterValue }
        $cursor = Get-JsoncSignificantIndex -Content $Content -Index $cursor -Limit $bounds.CloseIndex
    }

    return $properties.ToArray()
}

function Format-JsoncValue {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [string]$Indentation = ''
    )

    $json = ConvertTo-Json -InputObject $Value -Depth 20
    $newline = if ($json.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $json -split "`r?`n"
    if ($lines.Count -le 1) { return $json }
    return $lines[0] + $newline + (($lines[1..($lines.Count - 1)] | ForEach-Object { $Indentation + $_ }) -join $newline)
}

function Replace-TextRange {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$Start,
        [Parameter(Mandatory = $true)][int]$End,
        [Parameter(Mandatory = $true)][string]$Replacement
    )
    return $Content.Substring(0, $Start) + $Replacement + $Content.Substring($End)
}

function Merge-JsoncObjectContent {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)]$Desired
    )

    [void](ConvertFrom-Jsonc -Content $Content)
    $merged = $Content

    foreach ($desiredProperty in $Desired.PSObject.Properties) {
        $properties = @(Get-JsoncObjectProperties -Content $merged)
        $existing = @($properties | Where-Object { $_.Name -eq $desiredProperty.Name }) | Select-Object -Last 1

        if ($null -ne $existing) {
            $actualFirst = Get-JsoncSignificantIndex -Content $existing.ValueText -Index 0
            if ((Test-IsObjectNode -Value $desiredProperty.Value) -and
                $actualFirst -lt $existing.ValueText.Length -and
                $existing.ValueText[$actualFirst] -eq '{') {
                $replacement = Merge-JsoncObjectContent -Content $existing.ValueText -Desired $desiredProperty.Value
            }
            else {
                $replacement = Format-JsoncValue -Value $desiredProperty.Value -Indentation $existing.Indentation
            }
            $merged = Replace-TextRange -Content $merged -Start $existing.ValueStart -End $existing.ValueEnd -Replacement $replacement
            continue
        }

        $bounds = Get-JsoncObjectBounds -Content $merged
        $properties = @(Get-JsoncObjectProperties -Content $merged)
        if ($properties.Count -gt 0) {
            $last = $properties[$properties.Count - 1]
            if (-not $last.HasFollowingComma) {
                $merged = Replace-TextRange -Content $merged -Start $last.ValueEnd -End $last.ValueEnd -Replacement ','
                $bounds = Get-JsoncObjectBounds -Content $merged
                $properties = @(Get-JsoncObjectProperties -Content $merged)
            }
        }

        $newline = if ($merged.Contains("`r`n")) { "`r`n" } else { "`n" }
        $closeIndex = $bounds.CloseIndex
        $lineStart = $merged.LastIndexOf("`n", [Math]::Max(0, $closeIndex - 1))
        if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart++ }
        $closingIndent = $merged.Substring($lineStart, $closeIndex - $lineStart)
        $insertIndex = if ($closingIndent -match '^\s*$') { $lineStart } else { $closeIndex }
        if ($closingIndent -notmatch '^\s*$') { $closingIndent = '' }

        $propertyIndent = if ($properties.Count -gt 0 -and -not [string]::IsNullOrEmpty($properties[0].Indentation)) {
            $properties[0].Indentation
        }
        else {
            $closingIndent + '  '
        }
        $keyJson = ConvertTo-Json -InputObject $desiredProperty.Name -Compress
        $valueJson = Format-JsoncValue -Value $desiredProperty.Value -Indentation $propertyIndent
        $prefix = if ($insertIndex -eq $closeIndex -and $closeIndex -gt 0 -and $merged[$closeIndex - 1] -ne "`n") { $newline } else { '' }
        $insertion = "$prefix$propertyIndent$keyJson`: $valueJson$newline"
        $merged = Replace-TextRange -Content $merged -Start $insertIndex -End $insertIndex -Replacement $insertion
    }

    [void](ConvertFrom-Jsonc -Content $merged)
    return $merged
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

    $desired = Get-DesiredVSCodeSettings -Context $Context
    $content = ConvertTo-Json -InputObject $desired -Depth 20
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $content = Get-Content -LiteralPath $path -Raw
        $backupDirectory = Join-Path $Context.Paths.RootPath 'backups'
        if (-not (Test-Path -LiteralPath $backupDirectory)) {
            New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        }
        $backup = Join-Path $backupDirectory ("vscode-settings-{0}-{1}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID)
        Copy-Item -LiteralPath $path -Destination $backup -Force
        $content = Merge-JsoncObjectContent -Content $content -Desired $desired
    }

    $temporaryPath = "$path.env-setup.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $content, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $path -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
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
