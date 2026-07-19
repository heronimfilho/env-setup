# Recovery and troubleshooting

## The CLI appears inactive

Long-running native commands emit a heartbeat with elapsed time and process ID. The default interval is ten seconds and can be changed:

```powershell
.\setup.ps1 -HeartbeatSeconds 5
```

A global timeout can be applied to native commands:

```powershell
.\setup.ps1 -CommandTimeoutSeconds 900
```

## Resume a failed or interrupted run

```powershell
.\setup.ps1 -Resume
```

The current task and phase are persisted in `%LOCALAPPDATA%\env-setup\state.json`. The task is detected again before any changes are retried.

## Inspect the machine

```powershell
.\setup.ps1 -Doctor
.\setup.ps1 -Status
.\setup.ps1 -ShowLastLog
```

Use the stable error code shown beside a task failure when opening an issue.

## Create a support bundle

```powershell
.\setup.ps1 -CollectDiagnostics
```

The bundle contains the doctor report, task status, version, redacted plan/state, and the last redacted log. It masks home paths, email addresses, private-key blocks, and common secret fields. Review the ZIP before sharing it.

## Reset only the remembered menu choices

```powershell
.\setup.ps1 -ResetSelections
```

This removes `plan.json`; it does not uninstall software or delete task state.

## Repair configured tasks

```powershell
.\setup.ps1 -Resume -Repair
```

Repair mode reapplies selected tasks even when detection reports that they are already configured.

## Pending restart

When the summary reports that a restart is required, restart Windows and run:

```powershell
.\setup.ps1 -Resume
```
