#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.VSCode.ps1')

$jsonc = @'
{
  // Preserve URLs and comments.
  "url": "https://example.com/path",
  "nested": {
    "enabled": true,
  },
  /* block comment */
  "items": [1, 2,],
}
'@
$parsed = ConvertFrom-Jsonc -Content $jsonc
if ($parsed.url -ne 'https://example.com/path') { throw 'JSONC string parsing failed.' }
if (-not $parsed.nested.enabled) { throw 'JSONC object parsing failed.' }
if (@($parsed.items).Count -ne 2) { throw 'JSONC trailing comma parsing failed.' }

$actual = [pscustomobject]@{
    existing = 'preserved'
    setting = 'old'
    nested = [pscustomobject]@{
        preserved = 'keep'
        replace = 'old'
    }
}
$expected = [pscustomobject]@{
    setting = 'new'
    nested = [pscustomobject]@{
        replace = 'new'
        added = 1
    }
}
$merged = Set-ObjectProperties -Target $actual -Source $expected
if ($merged.existing -ne 'preserved' -or $merged.setting -ne 'new') { throw 'Settings merge failed.' }
if ($merged.nested.preserved -ne 'keep') { throw 'Nested settings were not preserved.' }
if ($merged.nested.replace -ne 'new' -or $merged.nested.added -ne 1) { throw 'Nested settings were not merged.' }
if (-not (Test-ObjectContainsProperties -Actual $merged -Expected $expected)) { throw 'Settings comparison failed.' }

$existingJsonc = @'
{
  // Preserve this top-level comment.
  "unrelated": true,
  "editor.codeActionsOnSave": {
    // Preserve this nested comment.
    "custom.action": "always",
    "source.fixAll.eslint": "never"
  }
}
'@
$desiredJsonc = [pscustomobject]@{
    'editor.codeActionsOnSave' = [pscustomobject]@{
        'source.fixAll.eslint' = 'explicit'
        'source.organizeImports' = 'explicit'
    }
    'editor.formatOnSave' = $true
}
$mergedJsonc = Merge-JsoncObjectContent -Content $existingJsonc -Desired $desiredJsonc
foreach ($comment in @('Preserve this top-level comment.', 'Preserve this nested comment.')) {
    if (-not $mergedJsonc.Contains($comment)) {
        throw "JSONC comment was not preserved: $comment"
    }
}
$parsedMergedJsonc = ConvertFrom-Jsonc -Content $mergedJsonc
if (-not $parsedMergedJsonc.unrelated) { throw 'An unrelated JSONC setting was removed.' }
if ($parsedMergedJsonc.'editor.codeActionsOnSave'.'custom.action' -ne 'always') { throw 'A nested JSONC setting was removed.' }
if ($parsedMergedJsonc.'editor.codeActionsOnSave'.'source.fixAll.eslint' -ne 'explicit') { throw 'A nested JSONC setting was not updated.' }
if ($parsedMergedJsonc.'editor.codeActionsOnSave'.'source.organizeImports' -ne 'explicit') { throw 'A nested JSONC setting was not added.' }
if (-not $parsedMergedJsonc.'editor.formatOnSave') { throw 'A top-level JSONC setting was not added.' }

$manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'config/vscode.extensions.json') -Raw | ConvertFrom-Json
foreach ($group in @('base', 'node', 'dotnet', 'delphi', 'devops')) {
    $definition = $manifest.PSObject.Properties[$group].Value
    if (@($definition.extensions).Count -eq 0) { throw "Extension group is empty: $group" }
}

Write-Host 'VS Code tests passed.'
