#Requires -Version 5.1
# ==============================================================================
# ConfigLoader.psm1 - Konfiguration laden (TdpBackup.config + BackupPlan.json)
# ==============================================================================

function Get-SystemConfig {
    param(
        [string]$ConfigPath = "C:\Program Files\Tivoli\TSM\TDPSql\TdpBackup.config"
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "Systemkonfiguration nicht gefunden: $ConfigPath`n`nBitte zuerst Setup-TdpBackup.ps1 ausführen!"
    }

    try {
        $config = Import-Clixml -Path $ConfigPath
        return $config
    }
    catch {
        throw "Fehler beim Laden der Systemkonfiguration: $_"
    }
}

function Get-BackupConfig {
    param(
        [string]$ConfigPath = "C:\Program Files\Tivoli\TSM\TDPSql\BackupPlan.json"
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "Backup-Konfiguration nicht gefunden: $ConfigPath"
    }

    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    return $config
}

function Add-DatabasesToBackupPlan {
    # Traegt neue Datenbanken dauerhaft in BackupPlan.json ein (und im uebergebenen
    # $Config-Objekt). Noetig, weil Sync-JsonToDatabase TDP_BackupPlan bei jedem Lauf
    # komplett aus der JSON neu aufbaut - nur in SQL angelegte Eintraege waeren am
    # naechsten Abend wieder weg.
    param(
        [object]$Config,
        [string]$ConfigPath,
        [string[]]$DatabaseNames
    )

    $added = @()
    foreach ($name in $DatabaseNames) {
        $added += [pscustomobject]@{
            Name                  = $name
            Enabled               = $true
            BackupType            = "FULL"
            IncludeInDifferential = $true
            Priority              = 50
            Notes                 = "Auto-added $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        }
    }

    $Config.SelectedDatabases = @($Config.SelectedDatabases) + $added
    if ($Config.PSObject.Properties['LastModified']) {
        $Config.LastModified = (Get-Date -Format 'yyyy-MM-dd')
    }

    # Atomar schreiben: erst Temp-Datei, dann ersetzen. UTF-8 ohne BOM.
    $json = $Config | ConvertTo-Json -Depth 10
    $tmp = "$ConfigPath.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -Path $tmp -Destination $ConfigPath -Force
}

function Sync-JsonToDatabase {
    param(
        [object]$Config,
        [string]$SqlServer,
        [string]$Database = "master"
    )

    Write-Host "Synchronisiere JSON-Konfiguration zu SQL Server..."

    try {
        $dbConnection = New-Object System.Data.SqlClient.SqlConnection
        $dbConnection.ConnectionString = "Server=$SqlServer;Database=$Database;Integrated Security=true;Connection Timeout=30"
        $dbConnection.Open()

        # Leere TDP_BackupPlan (alle alten Einträge entfernen)
        $cmd = $dbConnection.CreateCommand()
        $cmd.CommandText = "DELETE FROM [master].[dbo].[TDP_BackupPlan]"
        $cmd.ExecuteNonQuery() | Out-Null

        # Füge Datenbanken aus JSON ein
        foreach ($db in $Config.SelectedDatabases) {
            if ($db.Enabled) {
                $sql = @"
                INSERT INTO [master].[dbo].[TDP_BackupPlan]
                (DatabaseName, Enabled, IncludeInDifferential, BackupType, Priority, Notes, JsonSyncDate)
                VALUES (@DbName, @Enabled, @IncludeDiff, @BackupType, @Priority, @Notes, GETDATE())
"@

                $cmd = $dbConnection.CreateCommand()
                $cmd.CommandText = $sql
                $cmd.Parameters.AddWithValue("@DbName", $db.Name) | Out-Null
                $cmd.Parameters.AddWithValue("@Enabled", [int]$db.Enabled) | Out-Null
                $cmd.Parameters.AddWithValue("@IncludeDiff", [int]$db.IncludeInDifferential) | Out-Null
                $cmd.Parameters.AddWithValue("@BackupType", $db.BackupType) | Out-Null
                $cmd.Parameters.AddWithValue("@Priority", [int]$db.Priority) | Out-Null
                $notesValue = if ($db.Notes) { $db.Notes } else { "" }
                $cmd.Parameters.AddWithValue("@Notes", $notesValue) | Out-Null

                $cmd.ExecuteNonQuery() | Out-Null
                Write-Host "  ✓ $($db.Name) synchronisiert"
            }
        }

        # Für neu per JSON hinzugefügte DBs einen BackupStatus-Stub anlegen, sonst
        # sieht die Sonderbehandlung (v_DatabasesWithoutFullBackup) sie nie, da diese
        # View von BackupStatus ausgeht, nicht von TDP_BackupPlan.
        $ensureStatusSql = @"
        INSERT INTO [master].[dbo].[BackupStatus] (DatabaseName, FullBackupExists, CreatedDate)
        SELECT bp.DatabaseName, 0, GETDATE()
        FROM [master].[dbo].[TDP_BackupPlan] bp
        WHERE bp.Enabled = 1
          AND NOT EXISTS (SELECT 1 FROM [master].[dbo].[BackupStatus] bs WHERE bs.DatabaseName = bp.DatabaseName)
"@
        $ensureStatusCmd = $dbConnection.CreateCommand()
        $ensureStatusCmd.CommandText = $ensureStatusSql
        $ensureStatusCmd.ExecuteNonQuery() | Out-Null

        $dbConnection.Close()
        Write-Host "Synchronisierung abgeschlossen ✓"
        return $true
    }
    catch {
        Write-Error "Fehler beim Synchronisieren: $_"
        return $false
    }
}

Export-ModuleMember -Function Get-BackupConfig, Add-DatabasesToBackupPlan, Sync-JsonToDatabase
