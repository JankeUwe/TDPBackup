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
    SELECT DatabaseName, FullBackupSizeMB, LastFullBackupDate
    FROM [master].[dbo].[BackupStatus]
    WHERE FullBackupExists = 1 AND IsInBackupPlan = 1
    ORDER BY DatabaseName
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

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.Parameters.AddWithValue("@DbName", $DatabaseName) | Out-Null
    $cmd.Parameters.AddWithValue("@Type", $BackupType) | Out-Null
    $cmd.Parameters.AddWithValue("@Stat", $Status) | Out-Null
    $cmd.Parameters.AddWithValue("@Size", $SizeMB ?? [DBNull]::Value) | Out-Null
    $cmd.Parameters.AddWithValue("@Error", $ErrorMessage ?? [DBNull]::Value) | Out-Null
    $cmd.Parameters.AddWithValue("@Path", $BackupPath ?? [DBNull]::Value) | Out-Null

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

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.Parameters.AddWithValue("@DbName", $DatabaseName) | Out-Null
    $cmd.Parameters.AddWithValue("@Type", $BackupType) | Out-Null
    $cmd.Parameters.AddWithValue("@Stat", $Status) | Out-Null
    $cmd.Parameters.AddWithValue("@Start", $StartTime) | Out-Null
    $cmd.Parameters.AddWithValue("@End", $EndTime) | Out-Null
    $cmd.Parameters.AddWithValue("@Size", $SizeMB) | Out-Null
    $cmd.Parameters.AddWithValue("@Code", $ErrorCode) | Out-Null
    $cmd.Parameters.AddWithValue("@Error", $ErrorMessage ?? [DBNull]::Value) | Out-Null
    $cmd.Parameters.AddWithValue("@Path", $BackupPath ?? [DBNull]::Value) | Out-Null
    $cmd.Parameters.AddWithValue("@Note", $Notes ?? [DBNull]::Value) | Out-Null

    $cmd.ExecuteNonQuery() | Out-Null
}

Export-ModuleMember -Function Get-SqlConnection, Get-DatabasesWithoutFullBackup, Get-DatabasesForFullBackup, Get-DatabasesForDifferentialBackup, Update-BackupStatus, Log-BackupResult
