# ==============================================================================
# TdpBackupHelper.psm1 - TDP Backup-Befehle ausführen
# ==============================================================================

function Invoke-TdpBackup {
    param(
        [string]$DatabaseName,
        [string]$BackupType,  # FULL oder DIFF
        [string]$TdpDir,
        [string]$SqlServer,
        [string]$TsmPassword,
        [string]$TsmOptFile,
        [string]$TdpConfigFile,
        [string]$LogFile
    )

    $startTime = Get-Date

    # Validierung
    if ($BackupType -notin @("FULL", "DIFF")) {
        throw "Invalid BackupType: $BackupType (must be FULL or DIFF)"
    }

    # TDP-Befehl zusammenstellen
    $tdpBackupCmd = "$TdpDir\tdpsqlc.exe"

    if (-not (Test-Path $tdpBackupCmd)) {
        throw "TDP executable not found: $tdpBackupCmd"
    }

    Write-Host "[$BackupType] Starting backup for database: $DatabaseName"

    # TDP-Befehl ausführen
    $arguments = @(
        "backup",
        $DatabaseName,
        $BackupType.ToLower(),
        "/TSMPassword=$TsmPassword",
        "/SQLSERVer=$SqlServer",
        "/tsmoptfile=$TsmOptFile",
        "/configfile=$TdpConfigFile",
        "/logfile=$LogFile"
    )

    try {
        # Befehl ausführen (& startet externes Programm)
        & $tdpBackupCmd $arguments 2>&1 | Tee-Object -Variable output -ErrorAction SilentlyContinue

        $exitCode = $LASTEXITCODE
        $endTime = Get-Date
        $durationSeconds = [int]($endTime - $startTime).TotalSeconds

        if ($exitCode -eq 0) {
            Write-Host "[$BackupType] ✓ SUCCESS for $DatabaseName ($durationSeconds seconds)"

            return @{
                Success = $true
                DatabaseName = $DatabaseName
                BackupType = $BackupType
                StartTime = $startTime
                EndTime = $endTime
                DurationSeconds = $durationSeconds
                SizeMB = 0  # TODO: Parse aus TDP-Log
                ErrorMessage = $null
                ExitCode = $exitCode
            }
        }
        else {
            $errorMsg = $output -join "`n"
            Write-Host "[$BackupType] ✗ FAILED for $DatabaseName (Exit Code: $exitCode)"
            Write-Host $errorMsg

            return @{
                Success = $false
                DatabaseName = $DatabaseName
                BackupType = $BackupType
                StartTime = $startTime
                EndTime = $endTime
                DurationSeconds = $durationSeconds
                SizeMB = 0
                ErrorMessage = $errorMsg
                ExitCode = $exitCode
            }
        }
    }
    catch {
        $endTime = Get-Date
        $durationSeconds = [int]($endTime - $startTime).TotalSeconds

        Write-Host "[$BackupType] ✗ EXCEPTION for $DatabaseName: $_"

        return @{
            Success = $false
            DatabaseName = $DatabaseName
            BackupType = $BackupType
            StartTime = $startTime
            EndTime = $endTime
            DurationSeconds = $durationSeconds
            SizeMB = 0
            ErrorMessage = $_
            ExitCode = -1
        }
    }
}

function Test-TdpService {
    param(
        [string]$TdpDir
    )

    $tdpExe = "$TdpDir\tdpsqlc.exe"

    if (-not (Test-Path $tdpExe)) {
        Write-Error "TDP executable not found: $tdpExe"
        return $false
    }

    # Einfacher Test: Version abfragen
    try {
        & $tdpExe -? | Out-Null
        return $true
    }
    catch {
        Write-Error "TDP service test failed: $_"
        return $false
    }
}

function Ensure-LogDirectory {
    param(
        [string]$LogPath
    )

    if (-not (Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        Write-Host "Created log directory: $LogPath"
    }
}

Export-ModuleMember -Function Invoke-TdpBackup, Test-TdpService, Ensure-LogDirectory
