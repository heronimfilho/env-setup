# Troubleshooting

## WinGet appears stuck

The first WinGet query can take several minutes while sources initialize. The CLI emits a heartbeat containing elapsed time and the process ID. To use a shorter heartbeat interval:

```powershell
.\setup.ps1 -Resume -HeartbeatSeconds 5
```

To enforce a maximum native-command duration:

```powershell
.\setup.ps1 -Resume -CommandTimeoutSeconds 900
```

## WinGet is missing

Run:

```powershell
.\setup.ps1 -Doctor
```

Install or update **App Installer** from Microsoft Store, reopen PowerShell, and run the setup again.

## WSL requests a restart

Restart Windows, open an elevated PowerShell session, and continue:

```powershell
cd $HOME\env-setup
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1 -Resume
```

## WSL user initialization is pending

Open the selected distribution once, create the Linux username and password, close the window, and run `setup.ps1 -Resume`.

## GitHub authentication opens a browser

Complete the browser flow and return to the terminal. Non-interactive runs cannot perform first-time browser authentication; authenticate once interactively and resume.

## Visual Studio Code CLI is not found

Restart the terminal after Visual Studio Code installation so its command becomes available in `PATH`, then run `setup.ps1 -Resume`.

## A task fails repeatedly

Use the stable `ENVSETUP-*` error code and inspect:

```powershell
.\setup.ps1 -Status
.\setup.ps1 -ShowLastLog
.\setup.ps1 -CollectDiagnostics -DoctorSkipNetwork
```

Review the diagnostic ZIP before attaching it to an issue.

## Saved menu choices are incorrect

```powershell
.\setup.ps1 -ResetSelections
```

The command only removes remembered selections. It does not uninstall software or erase task history.

## A Git clone will not update

`setup.ps1 -Update` requires a clean working tree on `main`. Commit, stash, or discard local changes and return to `main` before retrying.

## JSON output contains an error

Run with an explicit non-interactive plan:

```powershell
.\setup.ps1 -Profile Core -Check -NonInteractive -OutputFormat Json -NoColor
```

Interactive menus are intentionally unavailable in JSON mode.
