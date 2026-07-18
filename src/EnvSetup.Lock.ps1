Set-StrictMode -Version Latest

function Enter-EnvSetupLock {
    param([Parameter(Mandatory = $true)]$Paths)

    if (Test-Path -LiteralPath $Paths.LockPath -PathType Leaf) {
        $existingLock = Read-JsonFile -Path $Paths.LockPath
        if ($null -ne $existingLock -and $null -ne $existingLock.processId) {
            $process = Get-Process -Id ([int]$existingLock.processId) -ErrorAction SilentlyContinue
            if ($null -ne $process) {
                throw "Another env-setup process is running with process ID $($existingLock.processId)."
            }
        }
        Remove-Item -LiteralPath $Paths.LockPath -Force -ErrorAction SilentlyContinue
    }

    $lock = [pscustomobject]@{
        processId = $PID
        startedAt = (Get-Date).ToUniversalTime().ToString('o')
        computer  = $env:COMPUTERNAME
    }
    Write-JsonFileAtomic -Value $lock -Path $Paths.LockPath
}

function Exit-EnvSetupLock {
    param([Parameter(Mandatory = $true)]$Paths)

    if (-not (Test-Path -LiteralPath $Paths.LockPath -PathType Leaf)) { return }
    $lock = Read-JsonFile -Path $Paths.LockPath
    if ($null -eq $lock -or [int]$lock.processId -eq $PID) {
        Remove-Item -LiteralPath $Paths.LockPath -Force -ErrorAction SilentlyContinue
    }
}
