#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'src/EnvSetup.Core.ps1')
. (Join-Path $projectRoot 'src/EnvSetup.VSCode.ps1')

$jsonc = @'
{
  // Preserve URLs and remove comments.
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

$actual = [pscustomobject]@{ existing = 'preserved'; setting = 'old' }
$expected = [pscustomobject]@{ setting = 'new'; nested = [pscustomobject]@{ value = 1 } }
$merged = Set-ObjectProperties -Target $actual -Source $expected
if ($merged.existing -ne 'preserved' -or $merged.setting -ne 'new') { throw 'Settings merge failed.' }
if (-not (Test-ObjectContainsProperties -Actual $merged -Expected $expected)) { throw 'Settings comparison failed.' }

$manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'config/vscode.extensions.json') -Raw | ConvertFrom-Json
foreach ($group in @('base', 'node', 'dotnet', 'delphi', 'devops')) {
    $definition = $manifest.PSObject.Properties[$group].Value
    if (@($definition.extensions).Count -eq 0) { throw "Extension group is empty: $group" }
}

Write-Host 'VS Code tests passed.'
