#Requires -Version 5.1
# ==============================================================================
# Backup-TdpFull.ps1 - FULL und DIFF Backups mit Sonderbehandlung
# Läuft täglich (z.B. 20:00 Uhr) und orchestriert:
#   1. SONDERBEHANDLUNG: DBs ohne FULL → sofort FULL
#   2. SONNTAG: Reguläre FULL-Backups
#   3. MO-SA: DIFF-Backups (nur wenn FULL existiert)
# ==============================================================================

param(
    [string]$ConfigPath = "C:\Program Files\Tivoli\TSM\TDPSql\BackupPlan.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ==============================================================================
# Initialisierung
# ==============================================================================

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulePath = Join-Path $ScriptPath "Modules"

# Module laden
Import-Module (Join-Path $ModulePath "ConfigLoader.psm1") -Force
Import-Module (Join-Path $ModulePath "SqlTracking.psm1") -Force
Import-Module (Join-Path $ModulePath "TdpBackupHelper.psm1") -Force

# Zeitstempel
$ExecutionTime = Get-Date
$LogTimestamp = $ExecutionTime.ToString("yyyyMMdd_HHmmss")
$DayOfWeek = $ExecutionTime.DayOfWeek

# Datenbanken, die in diesem Lauf bereits ein erfolgreiches FULL erhalten haben
# (Sonderbehandlung oder planmaessiges FULL) - brauchen am selben Abend kein DIFF mehr.
$fullDoneThisRun = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

function Invoke-FullBackupTracked {
    # FULL-Backup inkl. Status- und Log-Eintrag. Liest $TdpDir, $TSQLServer, $TSMPassword,
    # $TsmOptFile, $TdpConfigFile, $LogPath, $LogTimestamp aus dem Script-Scope (werden
    # in Step 1 gesetzt, bevor diese Funktion aufgerufen wird). Gibt $true bei Erfolg zurueck.
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$DatabaseName
    )

    $logFile = Join-Path $LogPath "backup_FULL_${DatabaseName}_$LogTimestamp.log"

    $result = Invoke-TdpBackup `
        -DatabaseName $DatabaseName `
        -BackupType "FULL" `
        -TdpDir $TdpDir `
        -SqlServer $TSQLServer `
        -TsmPassword $TSMPassword `
        -TsmOptFile $TsmOptFile `
        -TdpConfigFile $TdpConfigFile `
        -LogFile $logFile

    if ($result.Success) {
        Update-BackupStatus -Connection $Connection -DatabaseName $DatabaseName `
            -BackupType "FULL" -Status "SUCCESS" -BackupPath $logFile
        [void]$fullDoneThisRun.Add($DatabaseName)
    }
    else {
        Update-BackupStatus -Connection $Connection -DatabaseName $DatabaseName `
            -BackupType "FULL" -Status "FAILED" -ErrorMessage $result.ErrorMessage
    }

    $statusText = if ($result.Success) { "SUCCESS" } else { "FAILED" }
    Log-BackupResult `
        -Connection $Connection `
        -DatabaseName $DatabaseName `
        -BackupType "FULL" `
        -Status $statusText `
        -StartTime $result.StartTime `
        -EndTime $result.EndTime `
        -SizeMB $result.SizeMB `
        -ErrorCode $result.ExitCode `
        -ErrorMessage $result.ErrorMessage `
        -BackupPath $logFile

    if (-not $result.Success) {
        Write-Host "    ✗ FULL FAILED: $($result.ErrorMessage)"
    }
    return [bool]$result.Success
}

Write-Host ""
Write-Host "=============================================================================="
Write-Host "TDP Backup Orchestration"
Write-Host "Time: $ExecutionTime"
Write-Host "Day: $DayOfWeek"
Write-Host "=============================================================================="

try {
    # System-Konfiguration laden (.config)
    Write-Host ""
    Write-Host "Step 1: Loading system configuration..."
    $sysConfig = Get-SystemConfig
    Write-Host "  ✓ System config loaded"

    $TdpDirValue = $sysConfig.PSObject.Properties['TdpDir'].Value
    if ($TdpDirValue) { $TdpDir = $TdpDirValue } else { $TdpDir = "C:\Program Files\Tivoli\TSM\TDPSql" }
    $TSQLServer = $sysConfig.SQLInstance
    $TSMPassword = $sysConfig.TSMPassword
    $TsmOptFile = $sysConfig.TsmOptFile
    $TdpConfigFile = $sysConfig.TdpConfigFile
    $LogPath = "$TdpDir\03_Log"
    $FullBackupDay = "Sunday"

    # Backup-Plan laden (.json)
    Write-Host "Step 2: Loading backup plan..."
    $config = Get-BackupConfig -ConfigPath $ConfigPath
    Write-Host "  ✓ Backup plan loaded"

    # Schedule auslesen
    $fullBackupDays = $config.Schedule.FullBackupDays
    $diffBackupDays = $config.Schedule.DifferentialBackupDays
    $allowSpecialHandling = $config.Schedule.AllowSpecialHandling

    Write-Host "  📅 Szenario: $($config.Scenario)"
    Write-Host "  🔵 FULL-Backup: $($fullBackupDays -join ', ')"
    Write-Host "  🟢 DIFF-Backup: $(if ($diffBackupDays.Count -gt 0) { $diffBackupDays -join ', ' } else { 'Keine' })"

    # Log-Verzeichnis erstellen
    Ensure-LogDirectory -LogPath $LogPath

    # SQL-Verbindung
    Write-Host "Step 3: Connecting to SQL Server..."
    $dbConnection = Get-SqlConnection -SqlServer $TSQLServer
    Write-Host "  ✓ Connected to $TSQLServer"

    # Neue Datenbanken erkennen und dauerhaft in BackupPlan.json aufnehmen (opt-in).
    # Muss VOR dem Sync passieren: Sync baut TDP_BackupPlan komplett aus der JSON neu auf.
    $autoAddProp = $config.Schedule.PSObject.Properties['AutoAddNewDatabases']
    if ($autoAddProp -and $autoAddProp.Value) {
        Write-Host "Step 3b: Discovering new databases..."
        try {
            $knownNames = @($config.SelectedDatabases | ForEach-Object { $_.Name })
            $excludedProp = $config.PSObject.Properties['ExcludedDatabases']
            $excludedNames = if ($excludedProp -and $excludedProp.Value) { @($excludedProp.Value) } else { @() }

            $newDbs = @(Get-UnconfiguredDatabases -Connection $dbConnection -KnownNames $knownNames -ExcludedNames $excludedNames)
            if ($newDbs.Count -gt 0) {
                Add-DatabasesToBackupPlan -Config $config -ConfigPath $ConfigPath -DatabaseNames $newDbs
                Write-Host "  ✓ $($newDbs.Count) new database(s) added to BackupPlan.json: $($newDbs -join ', ')"
            }
            else {
                Write-Host "  ✓ No new databases found"
            }
        }
        catch {
            # Discovery ist Zusatz - ein Fehler hier darf die Sicherung nicht verhindern
            Write-Host "  ⚠ Database discovery failed (backup continues): $($_.Exception.Message)"
        }
    }

    # JSON zu SQL synchronisieren
    Write-Host "Step 4: Syncing configuration to database..."
    Sync-JsonToDatabase -Config $config -SqlServer $TSQLServer
    Write-Host "  ✓ Sync completed"

    # ==============================================================================
    # SONDERBEHANDLUNG: DBs ohne FULL-Backup → sofort FULL
    # ==============================================================================
    Write-Host ""
    Write-Host "Step 5: Special handling - databases without FULL backup..."

    if ($allowSpecialHandling) {
    $dbsWithoutFull = Get-DatabasesWithoutFullBackup -Connection $dbConnection

    if ($dbsWithoutFull.Count -gt 0) {
        Write-Host "  Found $($dbsWithoutFull.Count) database(s) without FULL backup:"

        foreach ($db in $dbsWithoutFull) {
            Write-Host ""
            Write-Host "  → Running immediate FULL backup for: $($db.DatabaseName)"

            $logFile = Join-Path $LogPath "backup_FULL_$($db.DatabaseName)_$LogTimestamp.log"

            $result = Invoke-TdpBackup `
                -DatabaseName $db.DatabaseName `
                -BackupType "FULL" `
                -TdpDir $TdpDir `
                -SqlServer $TSQLServer `
                -TsmPassword $TSMPassword `
                -TsmOptFile $TsmOptFile `
                -TdpConfigFile $TdpConfigFile `
                -LogFile $logFile

            # Status aktualisieren
            if ($result.Success) {
                Update-BackupStatus `
                    -Connection $dbConnection `
                    -DatabaseName $db.DatabaseName `
                    -BackupType "FULL" `
                    -Status "SUCCESS" `
                    -SizeMB 0 `
                    -BackupPath $logFile

                [void]$fullDoneThisRun.Add($db.DatabaseName)
                Write-Host "    ✓ Database $($db.DatabaseName) is now protected"
            }
            else {
                Update-BackupStatus `
                    -Connection $dbConnection `
                    -DatabaseName $db.DatabaseName `
                    -BackupType "FULL" `
                    -Status "FAILED" `
                    -ErrorMessage $result.ErrorMessage

                Write-Host "    ✗ FULL backup FAILED for $($db.DatabaseName)"
                Write-Host "       Error: $($result.ErrorMessage)"
            }

            # Log eintragen
            $statusText = if ($result.Success) { "SUCCESS" } else { "FAILED" }
            Log-BackupResult `
                -Connection $dbConnection `
                -DatabaseName $db.DatabaseName `
                -BackupType "FULL" `
                -Status $statusText `
                -StartTime $result.StartTime `
                -EndTime $result.EndTime `
                -SizeMB $result.SizeMB `
                -ErrorCode $result.ExitCode `
                -ErrorMessage $result.ErrorMessage `
                -BackupPath $logFile
        }
    }
    else {
        Write-Host "  ✓ No databases without FULL backup found"
    }
    }

    # ==============================================================================
    # REGULÄRE FULL-BACKUPS (je nach Schedule)
    # ==============================================================================
    if ($fullBackupDays -contains $DayOfWeek) {
        Write-Host ""
        Write-Host "Step 6: Scheduled day ($DayOfWeek) - Running FULL backups..."
        $dbsForFull = Get-DatabasesForFullBackup -Connection $dbConnection

        if ($dbsForFull.Count -gt 0) {
            Write-Host "  Found $($dbsForFull.Count) database(s) for FULL backup"

            foreach ($db in $dbsForFull) {
                Write-Host ""
                Write-Host "  → FULL: $($db.DatabaseName)"

                $logFile = Join-Path $LogPath "backup_FULL_$($db.DatabaseName)_$LogTimestamp.log"

                $result = Invoke-TdpBackup `
                    -DatabaseName $db.DatabaseName `
                    -BackupType "FULL" `
                    -TdpDir $TdpDir `
                    -SqlServer $TSQLServer `
                    -TsmPassword $TSMPassword `
                    -TsmOptFile $TsmOptFile `
                    -TdpConfigFile $TdpConfigFile `
                    -LogFile $logFile

                if ($result.Success) {
                    Update-BackupStatus `
                        -Connection $dbConnection `
                        -DatabaseName $db.DatabaseName `
                        -BackupType "FULL" `
                        -Status "SUCCESS" `
                        -BackupPath $logFile
                    [void]$fullDoneThisRun.Add($db.DatabaseName)
                    Write-Host "    ✓ Success"
                }
                else {
                    Update-BackupStatus `
                        -Connection $dbConnection `
                        -DatabaseName $db.DatabaseName `
                        -BackupType "FULL" `
                        -Status "FAILED" `
                        -ErrorMessage $result.ErrorMessage
                    Write-Host "    ✗ FAILED: $($result.ErrorMessage)"
                }

                $statusText = if ($result.Success) { "SUCCESS" } else { "FAILED" }
                Log-BackupResult `
                    -Connection $dbConnection `
                    -DatabaseName $db.DatabaseName `
                    -BackupType "FULL" `
                    -Status $statusText `
                    -StartTime $result.StartTime `
                    -EndTime $result.EndTime `
                    -SizeMB $result.SizeMB `
                    -ErrorCode $result.ExitCode `
                    -ErrorMessage $result.ErrorMessage `
                    -BackupPath $logFile
            }
        }
    }

    # ==============================================================================
    # SCHEDULED DIFF-BACKUPS (je nach Schedule)
    # ==============================================================================
    if ($diffBackupDays.Count -gt 0 -and $diffBackupDays -contains $DayOfWeek) {
        Write-Host ""
        Write-Host "Step 7: Scheduled day ($DayOfWeek) - Running DIFFERENTIAL backups..."
        $dbsForDiff = Get-DatabasesForDifferentialBackup -Connection $dbConnection

        if ($dbsForDiff.Count -gt 0) {
            Write-Host "  Found $($dbsForDiff.Count) database(s) for DIFF backup"

            foreach ($db in $dbsForDiff) {
                Write-Host ""

                # Heute schon ein FULL erhalten (Sonderbehandlung / planmaessig) -> kein DIFF noetig
                if ($fullDoneThisRun.Contains($db.DatabaseName)) {
                    Write-Host "  → SKIP DIFF: $($db.DatabaseName) (FULL already ran in this run)"
                    continue
                }

                # Diff-Basis gegen SQL Server pruefen, nicht dem Tracking-Flag vertrauen
                $baseState = Test-DifferentialBase -Connection $dbConnection -DatabaseName $db.DatabaseName
                if ($baseState -eq 'NotFound' -or $baseState -eq 'Offline') {
                    Write-Host "  → SKIP: $($db.DatabaseName) is $baseState on the server - no backup possible"
                    continue
                }
                if ($baseState -eq 'NoBase') {
                    Write-Host "  → $($db.DatabaseName): no differential base on the server (new/recreated/restored database)"
                    Write-Host "    Running FULL instead of DIFF"
                    Reset-FullBackupFlag -Connection $dbConnection -DatabaseName $db.DatabaseName
                    if (Invoke-FullBackupTracked -Connection $dbConnection -DatabaseName $db.DatabaseName) {
                        Write-Host "    ✓ FULL (instead of DIFF) succeeded - database is protected"
                    }
                    continue
                }

                Write-Host "  → DIFF: $($db.DatabaseName)"

                $logFile = Join-Path $LogPath "backup_DIFF_$($db.DatabaseName)_$LogTimestamp.log"

                $result = Invoke-TdpBackup `
                    -DatabaseName $db.DatabaseName `
                    -BackupType "DIFF" `
                    -TdpDir $TdpDir `
                    -SqlServer $TSQLServer `
                    -TsmPassword $TSMPassword `
                    -TsmOptFile $TsmOptFile `
                    -TdpConfigFile $TdpConfigFile `
                    -LogFile $logFile

                if ($result.Success) {
                    Update-BackupStatus `
                        -Connection $dbConnection `
                        -DatabaseName $db.DatabaseName `
                        -BackupType "DIFF" `
                        -Status "SUCCESS" `
                        -BackupPath $logFile
                    Write-Host "    ✓ Success"
                }
                else {
                    Update-BackupStatus `
                        -Connection $dbConnection `
                        -DatabaseName $db.DatabaseName `
                        -BackupType "DIFF" `
                        -Status "FAILED" `
                        -ErrorMessage $result.ErrorMessage
                    Write-Host "    ✗ FAILED: $($result.ErrorMessage)"
                }

                $statusText = if ($result.Success) { "SUCCESS" } else { "FAILED" }
                Log-BackupResult `
                    -Connection $dbConnection `
                    -DatabaseName $db.DatabaseName `
                    -BackupType "DIFF" `
                    -Status $statusText `
                    -StartTime $result.StartTime `
                    -EndTime $result.EndTime `
                    -SizeMB $result.SizeMB `
                    -ErrorCode $result.ExitCode `
                    -ErrorMessage $result.ErrorMessage `
                    -BackupPath $logFile
            }
        }
    }

    # Final report
    Write-Host ""
    Write-Host "=============================================================================="
    Write-Host "Backup Orchestration Completed"
    Write-Host "Execution Time: $(Get-Date)"
    Write-Host "=============================================================================="
    Write-Host ""

    $dbConnection.Close()
}
catch {
    Write-Error "FATAL ERROR: $_"
    Write-Error $_.Exception.StackTrace
    exit 1
}
