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
                $cmd.Parameters.AddWithValue("@Notes", $db.Notes ?? "") | Out-Null

                $cmd.ExecuteNonQuery() | Out-Null
                Write-Host "  ✓ $($db.Name) synchronisiert"
            }
        }

        $dbConnection.Close()
        Write-Host "Synchronisierung abgeschlossen ✓"
        return $true
    }
    catch {
        Write-Error "Fehler beim Synchronisieren: $_"
        return $false
    }
}

Export-ModuleMember -Function Get-BackupConfig, Sync-JsonToDatabase
