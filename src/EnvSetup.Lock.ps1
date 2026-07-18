Set-StrictMode -Version Latest

function Enter-EnvSetupLock {
    param([Parameter(Mandatory = $true)]$Paths)

    if (Test-Path -LiteralPath $Paths.LockPath -PathType Leaf) {
        $existingLock = $null
        try {
            $existingLock = Read-JsonFile -Path $Paths.LockPath
        }
        catch {
            Remove-Item -LiteralPath $Paths.LockPath -Force -ErrorAction SilentlyContinue
        }

        if ($null -ne $existingLock -and $null -ne $existingLock.processId) {
            $process = Get-Process -Id ([int]$existingLock.processId) -ErrorAction SilentlyContinue
            $sameProcess = $false
            if ($null -ne $process -and $null -ne $existingLock.processStartedAt) {
                $sameProcess = $process.StartTime.ToUniversalTime().ToString('o') -eq [string]$existingLock.processStartedAt
            }

            if ($sameProcess) {
                throw "Another env-setup process is running with process ID $($existingLock.processId)."
            }
        }
        Remove-Item -LiteralPath $Paths.LockPath -Force -ErrorAction SilentlyContinue
    }

    $currentProcess = Get-Process -Id $PID
    $lock = [pscustomobject]@{
        processId        = $PID
        processStartedAt = $currentProcess.StartTime.ToUniversalTime().ToString('o')
        createdAt        = (Get-Date).ToUniversalTime().ToString('o')
        computer         = $env:COMPUTERNAME
    }
    Write-JsonFileAtomic -Value $lock -Path $Paths.LockPath
}

function Exit-EnvSetupLock {
    param([Parameter(Mandatory = $true)]$Paths)

    if (-not (Test-Path -LiteralPath $Paths.LockPath -PathType Leaf)) { return }

    $lock = $null
    try {
        $lock = Read-JsonFile -Path $Paths.LockPath
    }
    catch {
        Remove-Item -LiteralPath $Paths.LockPath -Force -ErrorAction SilentlyContinue
        return
    }

    if ($null -eq $lock -or [int]$lock.processId -eq $PID) {
        Remove-Item -LiteralPath $Paths.LockPath -Force -ErrorAction SilentlyContinue
    }
}
