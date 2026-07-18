Set-StrictMode -Version Latest

$script:EnvSetupMutex = $null
$script:EnvSetupMutexName = $null

function Get-EnvSetupMutexName {
    param([Parameter(Mandatory = $true)][string]$LockPath)

    $normalizedPath = [System.IO.Path]::GetFullPath($LockPath).ToLowerInvariant()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedPath)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($bytes)
    }
    finally {
        $sha256.Dispose()
    }

    $hash = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    return "Local\env-setup-$hash"
}

function Enter-EnvSetupLock {
    param([Parameter(Mandatory = $true)]$Paths)

    if ($null -ne $script:EnvSetupMutex) {
        throw 'This process already holds the env-setup lock.'
    }

    $mutexName = Get-EnvSetupMutexName -LockPath $Paths.LockPath
    $mutex = [System.Threading.Mutex]::new($false, $mutexName)
    $acquired = $false

    try {
        try {
            $acquired = $mutex.WaitOne(0)
        }
        catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
        }

        if (-not $acquired) {
            throw 'Another env-setup process is already running.'
        }

        $script:EnvSetupMutex = $mutex
        $script:EnvSetupMutexName = $mutexName

        Remove-Item -LiteralPath $Paths.LockPath -Force -ErrorAction SilentlyContinue
        $currentProcess = Get-Process -Id $PID
        $lock = [pscustomobject]@{
            processId        = $PID
            processStartedAt = $currentProcess.StartTime.ToUniversalTime().ToString('o')
            createdAt        = (Get-Date).ToUniversalTime().ToString('o')
            computer         = $env:COMPUTERNAME
            mutexName        = $mutexName
        }
        Write-JsonFileAtomic -Value $lock -Path $Paths.LockPath
    }
    catch {
        if ($acquired) {
            try { $mutex.ReleaseMutex() } catch { }
        }
        $mutex.Dispose()
        $script:EnvSetupMutex = $null
        $script:EnvSetupMutexName = $null
        throw
    }
}

function Exit-EnvSetupLock {
    param([Parameter(Mandatory = $true)]$Paths)

    try {
        if (Test-Path -LiteralPath $Paths.LockPath -PathType Leaf) {
            $lock = $null
            try {
                $lock = Read-JsonFile -Path $Paths.LockPath
            }
            catch { }

            if ($null -eq $lock -or [int]$lock.processId -eq $PID) {
                Remove-Item -LiteralPath $Paths.LockPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    finally {
        if ($null -ne $script:EnvSetupMutex) {
            try { $script:EnvSetupMutex.ReleaseMutex() } catch { }
            $script:EnvSetupMutex.Dispose()
            $script:EnvSetupMutex = $null
            $script:EnvSetupMutexName = $null
        }
    }
}
