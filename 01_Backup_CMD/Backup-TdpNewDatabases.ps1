#Requires -Version 5.1
<#
.SYNOPSIS
    Sichert neue Datenbanken per FULL, damit "backup * difffull" und "backup * log"
    nicht an einer fehlenden Basis scheitern.

.DESCRIPTION
    Ergaenzt die bestehenden TDP-Jobs (Diff / FullWeekly / TLog), ohne sie zu veraendern.
    Die bestehenden Batch-Dateien mit "backup * difffull" bzw. "backup * log" bleiben
    unveraendert und sichern weiterhin ALLE Datenbanken.

    Das Skript fragt SQL Server selbst, welche Datenbanken noch keine Differential-Basis
    haben (sys.master_files.differential_base_lsn IS NULL, file_id = 1). Das trifft:
      - neu angelegte Datenbanken
      - gedroppte und gleichnamig neu erstellte Datenbanken
    und fuer jede davon laeuft  tdpsqlc backup <db> full.

    Ausgelassen werden: Systemdatenbanken (database_id <= 4), nicht-ONLINE-Datenbanken,
    Snapshots, lokale AG-Secondaries und Datenbanken, fuer die gerade ein BACKUP laeuft
    (z.B. der woechentliche "backup * full"). Erfolg zaehlt erst, wenn SQL Server danach
    eine Basis kennt - der TDP-Exit-Code allein reicht nicht.

    Exit-Code 0 = nichts zu tun oder alles erfolgreich, 1 = mindestens ein FULL fehlgeschlagen.

.PARAMETER SqlInstance
    Instanzname wie bei /SQLSERVer= in den bestehenden cmd-Dateien.

.PARAMETER DryRun
    Zeigt nur, welche Datenbanken ein FULL bekaemen, und sichert nichts.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SqlInstance,

    [string]$TdpDir = "C:\Program Files\Tivoli\TSM\TDPSql",
    [string]$TdpExe,
    [string]$TsmOptFile,
    [string]$TdpConfigFile,
    [string]$LogDir,

    [string[]]$ExcludeDatabases = @(),

    # Optional: SQL-Anmeldung statt Windows-Anmeldung (Standard: Windows-Anmeldung wie der Agent-Dienst)
    [System.Management.Automation.PSCredential]$SqlCredential,
    [switch]$TrustServerCertificate,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $TdpExe)        { $TdpExe        = Join-Path $TdpDir "tdpsqlc.exe" }
if (-not $TsmOptFile)    { $TsmOptFile    = Join-Path $TdpDir "dsm.opt" }
if (-not $TdpConfigFile) { $TdpConfigFile = Join-Path $TdpDir "tdpsql.cfg" }
if (-not $LogDir)        { $LogDir        = Join-Path $TdpDir "03_Log" }

function Write-Log {
    param([string]$Message)
    $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $Message
    Write-Output $line
    try { Add-Content -Path (Join-Path $LogDir "newdb_full_summary.log") -Value $line } catch { }
}

function Get-OpenConnection {
    $cs = "Server=$SqlInstance;Database=master;Connection Timeout=30;Application Name=TdpNewDatabasesFull"
    if ($TrustServerCertificate) { $cs += ";TrustServerCertificate=True" }

    if ($SqlCredential) {
        $pw = $SqlCredential.Password.Copy()
        $pw.MakeReadOnly()
        $cred = New-Object System.Data.SqlClient.SqlCredential($SqlCredential.UserName, $pw)
        $cn = New-Object System.Data.SqlClient.SqlConnection($cs, $cred)
    }
    else {
        $cn = New-Object System.Data.SqlClient.SqlConnection("$cs;Integrated Security=true")
    }
    $cn.Open()
    return $cn
}

function Get-DatabasesNeedingFull {
    param([System.Data.SqlClient.SqlConnection]$Connection)

    # Zwei Teile: (1) Datenbanken ohne Basis, (2) davon die, fuer die gerade ein BACKUP laeuft
    $sql = @"
    SELECT d.name,
           CASE WHEN EXISTS (SELECT 1 FROM sys.dm_exec_requests r
                             WHERE r.database_id = d.database_id AND r.command LIKE 'BACKUP%')
                THEN 1 ELSE 0 END AS backup_running
    FROM sys.databases d
    INNER JOIN sys.master_files mf ON mf.database_id = d.database_id AND mf.file_id = 1
    WHERE d.database_id > 4
      AND d.state_desc = 'ONLINE'
      AND d.source_database_id IS NULL
      AND mf.differential_base_lsn IS NULL
      AND NOT EXISTS (
            SELECT 1 FROM sys.dm_hadr_database_replica_states rs
            WHERE rs.database_id = d.database_id AND rs.is_local = 1 AND rs.is_primary_replica = 0)
    ORDER BY d.name
"@
    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $sql
    $reader = $cmd.ExecuteReader()
    $rows = @()
    while ($reader.Read()) {
        $rows += [pscustomobject]@{
            Name          = [string]$reader["name"]
            BackupRunning = ([int]$reader["backup_running"] -eq 1)
        }
    }
    $reader.Close()
    return $rows
}

function Test-HasDifferentialBase {
    param([System.Data.SqlClient.SqlConnection]$Connection, [string]$DatabaseName)

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = "SELECT COUNT(*) FROM sys.master_files WHERE database_id = DB_ID(@n) AND file_id = 1 AND differential_base_lsn IS NOT NULL"
    [void]$cmd.Parameters.AddWithValue("@n", $DatabaseName)
    return ([int]$cmd.ExecuteScalar() -gt 0)
}

# ------------------------------------------------------------------------------
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

# Nie zwei Laeufe gleichzeitig (z.B. stuendlicher Log-Job ueberlappt mit langem FULL)
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($false, "Global\TdpNewDatabasesFull", [ref]$createdNew)
if (-not $mutex.WaitOne(0)) {
    Write-Log "Another run of Backup-TdpNewDatabases is still active - nothing to do."
    exit 0
}

$failed = 0
try {
    if (-not $DryRun -and -not (Test-Path $TdpExe)) {
        throw "TDP executable not found: $TdpExe"
    }

    $cn = Get-OpenConnection
    try {
        $candidates = @(Get-DatabasesNeedingFull -Connection $cn)
        $todo = @()
        foreach ($c in $candidates) {
            if ($ExcludeDatabases -contains $c.Name) { Write-Log "SKIP $($c.Name): excluded by parameter"; continue }
            if ($c.BackupRunning)                    { Write-Log "SKIP $($c.Name): a backup is running right now (next run will re-check)"; continue }
            $todo += $c.Name
        }

        if ($todo.Count -eq 0) {
            Write-Log "No database without differential base - nothing to do."
            exit 0
        }

        Write-Log "Databases without differential base: $($todo -join ', ')"

        foreach ($name in $todo) {
            if ($DryRun) { Write-Log "DRYRUN would run: tdpsqlc backup `"$name`" full"; continue }

            $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $safe  = ($name -replace '[^\w\.-]', '_')
            $tdpLog = Join-Path $LogDir "backup_NEWDB_FULL_${safe}_$stamp.log"
            Write-Log "FULL start: $name"

            $tdpArgs = @(
                "backup", $name, "full",
                "/SQLSERVer=$SqlInstance",
                "/tsmoptfile=$TsmOptFile",
                "/configfile=$TdpConfigFile",
                "/logfile=$tdpLog"
            )

            # Wie in den bestehenden cmd-Dateien: im TDP-Verzeichnis ausfuehren
            Push-Location $TdpDir
            try {
                $out = & $TdpExe @tdpArgs 2>&1
                $exit = $LASTEXITCODE
            }
            finally { Pop-Location }

            # Erfolg erst, wenn SQL Server wirklich eine Basis kennt
            $hasBase = Test-HasDifferentialBase -Connection $cn -DatabaseName $name
            if ($exit -eq 0 -and $hasBase) {
                Write-Log "FULL ok: $name"
            }
            else {
                $failed++
                Write-Log "FULL FAILED: $name (tdpsqlc exit code $exit, differential base present: $hasBase)"
                $out | Select-Object -Last 15 | ForEach-Object { Write-Log "    $_" }
            }
        }
    }
    finally {
        $cn.Close()
    }
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    $failed++
}
finally {
    [void]$mutex.ReleaseMutex()
    $mutex.Dispose()
}

if ($failed -gt 0) { exit 1 }
exit 0
