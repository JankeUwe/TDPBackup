#Requires -Version 5.1
# ==============================================================================
# SqlTracking.psm1 - SQL Server Datenbankoperationen
# ==============================================================================

function Get-SqlConnection {
    param(
        [string]$SqlServer,
        [string]$Database = "master"
    )

    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = "Server=$SqlServer;Database=$Database;Integrated Security=true;Connection Timeout=30"

    try {
        $connection.Open()
        return $connection
    }
    catch {
        throw "Verbindung zu SQL Server fehlgeschlagen: $_"
    }
}

function Get-DatabasesWithoutFullBackup {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection
    )

    $sql = @"
    SELECT DatabaseName, Notes, DaysSinceAdded, LastErrorMessage
    FROM [master].[dbo].[v_DatabasesWithoutFullBackup]
    ORDER BY DaysSinceAdded DESC
"@

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $sql

    $reader = $cmd.ExecuteReader()
    $results = @()

    while ($reader.Read()) {
        $results += @{
            DatabaseName = $reader["DatabaseName"]
            Notes = $reader["Notes"]
            DaysSinceAdded = $reader["DaysSinceAdded"]
            LastErrorMessage = $reader["LastErrorMessage"]
        }
    }

    $reader.Close()
    return $results
}

function Get-DatabasesForFullBackup {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection
    )

    $sql = @"
    SELECT bp.DatabaseName, bs.FullBackupSizeMB, bs.LastFullBackupDate
    FROM [master].[dbo].[TDP_BackupPlan] bp
    INNER JOIN [master].[dbo].[BackupStatus] bs ON bp.DatabaseName = bs.DatabaseName
    WHERE bp.Enabled = 1 AND bs.FullBackupExists = 1
    ORDER BY bp.Priority DESC, bp.DatabaseName
"@

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $sql

    $reader = $cmd.ExecuteReader()
    $results = @()

    while ($reader.Read()) {
        $results += @{
            DatabaseName = $reader["DatabaseName"]
            FullBackupSizeMB = $reader["FullBackupSizeMB"]
            LastFullBackupDate = $reader["LastFullBackupDate"]
        }
    }

    $reader.Close()
    return $results
}

function Get-DatabasesForDifferentialBackup {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection
    )

    $sql = @"
    SELECT bp.DatabaseName, bs.LastDifferentialDate, bs.FullBackupSizeMB
    FROM [master].[dbo].[TDP_BackupPlan] bp
    INNER JOIN [master].[dbo].[BackupStatus] bs ON bp.DatabaseName = bs.DatabaseName
    WHERE bp.Enabled = 1
      AND bp.IncludeInDifferential = 1
      AND bs.FullBackupExists = 1
    ORDER BY bp.Priority DESC, bp.DatabaseName
"@

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $sql

    $reader = $cmd.ExecuteReader()
    $results = @()

    while ($reader.Read()) {
        $results += @{
            DatabaseName = $reader["DatabaseName"]
            LastDifferentialDate = $reader["LastDifferentialDate"]
            FullBackupSizeMB = $reader["FullBackupSizeMB"]
        }
    }

    $reader.Close()
    return $results
}

function Test-DifferentialBase {
    # Prueft gegen SQL Server selbst (nicht gegen die Tracking-Tabelle), ob fuer die
    # Datenbank eine Differential-Basis existiert. Gibt zurueck:
    #   'Ok'       - differential_base_lsn gesetzt, Diff moeglich
    #   'NoBase'   - Datenbank existiert, aber noch kein FULL seit Anlage/Restore
    #                (z.B. neu angelegt, oder gedroppt + gleichnamig neu erstellt)
    #   'NotFound' - Datenbank existiert nicht (mehr) auf dem Server
    #   'Offline'  - Datenbank nicht ONLINE, Backup nicht moeglich
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$DatabaseName
    )

    $sql = @"
    SELECT d.state_desc, mf.differential_base_lsn
    FROM sys.databases d
    INNER JOIN sys.master_files mf ON mf.database_id = d.database_id AND mf.file_id = 1
    WHERE d.name = @DbName
"@

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.Parameters.AddWithValue("@DbName", $DatabaseName) | Out-Null

    $reader = $cmd.ExecuteReader()
    try {
        if (-not $reader.Read()) { return 'NotFound' }
        if ($reader["state_desc"] -ne 'ONLINE') { return 'Offline' }
        if ($reader["differential_base_lsn"] -is [DBNull]) { return 'NoBase' }
        return 'Ok'
    }
    finally {
        $reader.Close()
    }
}

function Reset-FullBackupFlag {
    # Setzt das Tracking-Flag zurueck, wenn SQL Server keine Diff-Basis kennt.
    # Danach greift bei Bedarf auch die Sonderbehandlung (Schritt 5) am naechsten Lauf.
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$DatabaseName
    )

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = "UPDATE [master].[dbo].[BackupStatus] SET FullBackupExists = 0, DifferentialAllowed = 0, LastCheckedDate = GETDATE() WHERE DatabaseName = @DbName"
    $cmd.Parameters.AddWithValue("@DbName", $DatabaseName) | Out-Null
    $cmd.ExecuteNonQuery() | Out-Null
}

function Get-UnconfiguredDatabases {
    # Liefert ONLINE-Benutzerdatenbanken, die weder in BackupPlan.json (SelectedDatabases,
    # egal ob Enabled oder nicht) noch in ExcludedDatabases stehen. Eine bewusst mit
    # Enabled=false eingetragene Datenbank gilt als bekannt und wird nicht erneut angelegt.
    # Snapshots und lokale AG-Secondaries werden ausgelassen (dort ist kein Backup moeglich).
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string[]]$KnownNames = @(),
        [string[]]$ExcludedNames = @()
    )

    $sql = @"
    SELECT d.name
    FROM sys.databases d
    WHERE d.database_id > 4
      AND d.state_desc = 'ONLINE'
      AND d.source_database_id IS NULL
      AND NOT EXISTS (
            SELECT 1 FROM sys.dm_hadr_database_replica_states rs
            WHERE rs.database_id = d.database_id AND rs.is_local = 1 AND rs.is_primary_replica = 0)
    ORDER BY d.name
"@

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $sql

    $reader = $cmd.ExecuteReader()
    $names = @()
    while ($reader.Read()) { $names += [string]$reader["name"] }
    $reader.Close()

    # -notcontains ist case-insensitiv, passend zur ueblichen SQL-Server-Collation
    return @($names | Where-Object { ($KnownNames -notcontains $_) -and ($ExcludedNames -notcontains $_) })
}

function Update-BackupStatus {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$DatabaseName,
        [string]$BackupType,
        [string]$Status,
        [decimal]$SizeMB = $null,
        [string]$ErrorMessage = $null,
        [string]$BackupPath = $null
    )

    $sql = "EXEC [master].[dbo].[sp_UpdateBackupStatus] @DatabaseName=@DbName, @BackupType=@Type, @Status=@Stat, @SizeMB=@Size, @ErrorMessage=@Error, @BackupPath=@Path"

    $sizeMBParam = if ($null -eq $SizeMB) { [DBNull]::Value } else { $SizeMB }
    $errorMessageParam = if ($null -eq $ErrorMessage) { [DBNull]::Value } else { $ErrorMessage }
    $backupPathParam = if ($null -eq $BackupPath) { [DBNull]::Value } else { $BackupPath }

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.Parameters.AddWithValue("@DbName", $DatabaseName) | Out-Null
    $cmd.Parameters.AddWithValue("@Type", $BackupType) | Out-Null
    $cmd.Parameters.AddWithValue("@Stat", $Status) | Out-Null
    $cmd.Parameters.AddWithValue("@Size", $sizeMBParam) | Out-Null
    $cmd.Parameters.AddWithValue("@Error", $errorMessageParam) | Out-Null
    $cmd.Parameters.AddWithValue("@Path", $backupPathParam) | Out-Null

    $cmd.ExecuteNonQuery() | Out-Null
}

function Log-BackupResult {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$DatabaseName,
        [string]$BackupType,
        [string]$Status,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [decimal]$SizeMB,
        [int]$ErrorCode = 0,
        [string]$ErrorMessage = $null,
        [string]$BackupPath = $null,
        [string]$Notes = $null
    )

    $sql = @"
    EXEC [master].[dbo].[sp_LogBackupResult]
        @DatabaseName=@DbName,
        @BackupType=@Type,
        @Status=@Stat,
        @StartTime=@Start,
        @EndTime=@End,
        @SizeMB=@Size,
        @ErrorCode=@Code,
        @ErrorMessage=@Error,
        @BackupPath=@Path,
        @Notes=@Note
"@

    $errorMessageParam = if ($null -eq $ErrorMessage) { [DBNull]::Value } else { $ErrorMessage }
    $backupPathParam = if ($null -eq $BackupPath) { [DBNull]::Value } else { $BackupPath }
    $notesParam = if ($null -eq $Notes) { [DBNull]::Value } else { $Notes }

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.Parameters.AddWithValue("@DbName", $DatabaseName) | Out-Null
    $cmd.Parameters.AddWithValue("@Type", $BackupType) | Out-Null
    $cmd.Parameters.AddWithValue("@Stat", $Status) | Out-Null
    $cmd.Parameters.AddWithValue("@Start", $StartTime) | Out-Null
    $cmd.Parameters.AddWithValue("@End", $EndTime) | Out-Null
    $cmd.Parameters.AddWithValue("@Size", $SizeMB) | Out-Null
    $cmd.Parameters.AddWithValue("@Code", $ErrorCode) | Out-Null
    $cmd.Parameters.AddWithValue("@Error", $errorMessageParam) | Out-Null
    $cmd.Parameters.AddWithValue("@Path", $backupPathParam) | Out-Null
    $cmd.Parameters.AddWithValue("@Note", $notesParam) | Out-Null

    $cmd.ExecuteNonQuery() | Out-Null
}

Export-ModuleMember -Function Get-SqlConnection, Get-DatabasesWithoutFullBackup, Get-DatabasesForFullBackup, Get-DatabasesForDifferentialBackup, Test-DifferentialBase, Reset-FullBackupFlag, Get-UnconfiguredDatabases, Update-BackupStatus, Log-BackupResult
