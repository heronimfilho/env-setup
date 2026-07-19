# Adding a task

A task is a PowerShell object consumed by the shared runner.

## Required fields

```powershell
[pscustomobject]@{
    Id            = 'category.component'
    Name          = 'User-facing name'
    Category      = 'Category'
    Default       = $false
    Profiles      = @('Backend', 'Full')
    RequiresAdmin = $false
    Dependencies  = @('category.dependency')
    Detect        = { param($Context) $true }
    Apply         = { param($Context) }
    Verify        = { param($Context) $true }
}
```

## Rules

- IDs are stable, lowercase, and namespaced.
- `Detect` and `Verify` are read-only.
- `Apply` can be executed repeatedly without corrupting configuration.
- Dependencies contain task IDs, never display names.
- Interactive operations must be detectable so non-interactive runs can skip them when already configured.
- Remote downloads use immutable versions and validate a checksum when the publisher provides one.
- Existing files are backed up before managed content is changed.
- Secrets and private keys are never added to plan, state, logs, or diagnostics.

## Progress messages

Generated tasks may add:

```powershell
DetectMessage = 'Checking the component...'
ApplyMessage  = 'Installing the component...'
VerifyMessage = 'Verifying the component...'
```

Native commands automatically receive heartbeat, timeout, output capture, and logging through `Invoke-NativeCommand`.

## Testing checklist

- missing component is detected;
- configured component is detected;
- apply followed by verify succeeds;
- second execution performs no changes;
- repair execution is safe;
- check and dry-run remain read-only;
- failure persists the correct phase and error code;
- paths with spaces and special characters are covered when relevant.
