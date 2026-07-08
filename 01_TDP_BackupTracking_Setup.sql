-- ============================================================================
-- TDP Backup Tracking - SQL Setup Script (KORRIGIERT)
-- Für: Bank-Kunden mit flexibler DB-Selection und Audit-Trail
-- Author: Janke / Claude Code
-- Date: 2026-07-08
-- Updated: 2026-07-08 (Fehler Msg 241, Msg 4104 behoben)
-- ============================================================================
-- HINWEIS: Dieses Script wird auf dem SQL Server ausgeführt
--          und erstellt alle notwendigen Tabellen, Trigger und Stored Procedures
--          in der [master] Datenbank.
--
-- VERWENDUNG (alle Server-Varianten):
--   sqlcmd -S SRPSDSQL011 -i "01_TDP_BackupTracking_Setup.sql"
--   sqlcmd -S SRPSDSQL012 -i "01_TDP_BackupTracking_Setup.sql"
--   sqlcmd -S [dein-sql-server] -i "01_TDP_BackupTracking_Setup.sql"
-- ============================================================================

USE [master]
GO

PRINT '========== TDP Backup Tracking Setup =========='
PRINT 'Server: ' + @@SERVERNAME
PRINT 'Schritt 1: Tabellen erstellen...'
GO

-- ============================================================================
-- TABLE 1: TDP_BackupPlan (Konfiguration - Spiegelbild der JSON-Datei)
-- ============================================================================
IF OBJECT_ID('[dbo].[TDP_BackupPlan]', 'U') IS NOT NULL
    DROP TABLE [dbo].[TDP_BackupPlan]
GO

CREATE TABLE [dbo].[TDP_BackupPlan] (
    [Id] INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    [DatabaseName] SYSNAME NOT NULL UNIQUE,
    [Enabled] BIT NOT NULL DEFAULT 1,
    [IncludeInDifferential] BIT NOT NULL DEFAULT 1,
    [BackupType] VARCHAR(20) NOT NULL DEFAULT 'FULL',
    [Priority] INT DEFAULT 50,
    [Notes] NVARCHAR(MAX),
    [CreatedDate] DATETIME2(3) NOT NULL DEFAULT GETDATE(),
    [ModifiedDate] DATETIME2(3) NOT NULL DEFAULT GETDATE(),
    [ModifiedBy] SYSNAME DEFAULT SUSER_SNAME(),
    [JsonSyncDate] DATETIME2(3),
    [IsNewDatabase] BIT DEFAULT 0,
    CHECK ([Enabled] IN (0, 1)),
    CHECK ([Priority] >= 1 AND [Priority] <= 100)
)
GO

CREATE INDEX IX_TDP_BackupPlan_Enabled ON [dbo].[TDP_BackupPlan]([Enabled])
CREATE INDEX IX_TDP_BackupPlan_ModifiedDate ON [dbo].[TDP_BackupPlan]([ModifiedDate] DESC)
GO

PRINT 'TDP_BackupPlan erstellt ✓'
GO

-- ============================================================================
-- TABLE 2: TDP_BackupPlan_Audit (Audit-Trail für Compliance)
-- ============================================================================
IF OBJECT_ID('[dbo].[TDP_BackupPlan_Audit]', 'U') IS NOT NULL
    DROP TABLE [dbo].[TDP_BackupPlan_Audit]
GO

CREATE TABLE [dbo].[TDP_BackupPlan_Audit] (
    [AuditId] BIGINT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    [DatabaseName] SYSNAME NOT NULL,
    [Action] VARCHAR(10) NOT NULL,
    [OldEnabled] BIT,
    [NewEnabled] BIT,
    [OldIncludeInDifferential] BIT,
    [NewIncludeInDifferential] BIT,
    [OldNotes] NVARCHAR(MAX),
    [NewNotes] NVARCHAR(MAX),
    [ChangedBy] SYSNAME DEFAULT SUSER_SNAME(),
    [ChangedDate] DATETIME2(3) NOT NULL DEFAULT GETDATE(),
    [Reason] NVARCHAR(MAX),
    [IPAddress] NVARCHAR(50),
    [AuditType] VARCHAR(20) DEFAULT 'CONFIG'
)
GO

CREATE INDEX IX_TDP_BackupPlan_Audit_Date ON [dbo].[TDP_BackupPlan_Audit]([ChangedDate] DESC)
CREATE INDEX IX_TDP_BackupPlan_Audit_DB ON [dbo].[TDP_BackupPlan_Audit]([DatabaseName])
GO

PRINT 'TDP_BackupPlan_Audit erstellt ✓'
GO

-- ============================================================================
-- TABLE 3: BackupStatus
-- ============================================================================
IF OBJECT_ID('[dbo].[BackupStatus]', 'U') IS NOT NULL
    DROP TABLE [dbo].[BackupStatus]
GO

CREATE TABLE [dbo].[BackupStatus] (
    [Id] INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    [DatabaseName] SYSNAME NOT NULL UNIQUE,
    [FullBackupExists] BIT NOT NULL DEFAULT 0,
    [LastFullBackupDate] DATETIME2(3),
    [LastFullBackupPath] NVARCHAR(MAX),
    [LastFullBackupStatus] VARCHAR(20),
    [FullBackupSizeMB] DECIMAL(18,2),
    [LastDifferentialDate] DATETIME2(3),
    [DifferentialAllowed] BIT DEFAULT 0,
    [LastErrorMessage] NVARCHAR(MAX),
    [ConsecutiveFailures] INT DEFAULT 0,
    [IsInBackupPlan] BIT DEFAULT 0,
    [CreatedDate] DATETIME2(3) NOT NULL DEFAULT GETDATE(),
    [LastCheckedDate] DATETIME2(3),
    [Notes] NVARCHAR(MAX),
    CHECK ([FullBackupExists] IN (0, 1)),
    CHECK ([DifferentialAllowed] IN (0, 1))
)
GO

CREATE INDEX IX_BackupStatus_FullBackupExists ON [dbo].[BackupStatus]([FullBackupExists])
CREATE INDEX IX_BackupStatus_LastFullBackupDate ON [dbo].[BackupStatus]([LastFullBackupDate] DESC)
GO

PRINT 'BackupStatus erstellt ✓'
GO

-- ============================================================================
-- TABLE 4: BackupLog
-- ============================================================================
IF OBJECT_ID('[dbo].[BackupLog]', 'U') IS NOT NULL
    DROP TABLE [dbo].[BackupLog]
GO

CREATE TABLE [dbo].[BackupLog] (
    [LogId] BIGINT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    [ExecutionDate] DATETIME2(3) NOT NULL DEFAULT GETDATE(),
    [DatabaseName] SYSNAME NOT NULL,
    [BackupType] VARCHAR(20) NOT NULL,
    [Status] VARCHAR(20) NOT NULL,
    [StartTime] DATETIME2(3),
    [EndTime] DATETIME2(3),
    [DurationSeconds] INT,
    [BackupSizeMB] DECIMAL(18,2),
    [BackupPath] NVARCHAR(MAX),
    [ErrorCode] INT,
    [ErrorMessage] NVARCHAR(MAX),
    [TdpJobId] NVARCHAR(100),
    [RetryAttempt] INT DEFAULT 1,
    [Notes] NVARCHAR(MAX),
    [ExecutedBy] SYSNAME DEFAULT SUSER_SNAME()
)
GO

CREATE INDEX IX_BackupLog_Date ON [dbo].[BackupLog]([ExecutionDate] DESC)
CREATE INDEX IX_BackupLog_Database ON [dbo].[BackupLog]([DatabaseName])
CREATE INDEX IX_BackupLog_Status ON [dbo].[BackupLog]([Status])
GO

PRINT 'BackupLog erstellt ✓'
GO

-- ============================================================================
-- TABLE 5: BackupLog_Errors
-- ============================================================================
IF OBJECT_ID('[dbo].[BackupLog_Errors]', 'U') IS NOT NULL
    DROP TABLE [dbo].[BackupLog_Errors]
GO

CREATE TABLE [dbo].[BackupLog_Errors] (
    [ErrorId] BIGINT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    [LogId] BIGINT NOT NULL,
    [DatabaseName] SYSNAME NOT NULL,
    [BackupType] VARCHAR(20),
    [ErrorDate] DATETIME2(3) DEFAULT GETDATE(),
    [ErrorCode] INT,
    [ErrorMessage] NVARCHAR(MAX),
    [Severity] VARCHAR(20) DEFAULT 'ERROR',
    [IsResolved] BIT DEFAULT 0,
    [ResolutionNotes] NVARCHAR(MAX),
    [ResolvedBy] SYSNAME,
    [ResolvedDate] DATETIME2(3),
    FOREIGN KEY ([LogId]) REFERENCES [dbo].[BackupLog]([LogId]) ON DELETE CASCADE
)
GO

CREATE INDEX IX_BackupLog_Errors_Date ON [dbo].[BackupLog_Errors]([ErrorDate] DESC)
CREATE INDEX IX_BackupLog_Errors_Severity ON [dbo].[BackupLog_Errors]([Severity])
CREATE INDEX IX_BackupLog_Errors_Resolved ON [dbo].[BackupLog_Errors]([IsResolved])
GO

PRINT 'BackupLog_Errors erstellt ✓'
GO

-- ============================================================================
-- TABLE 6: DatabaseDiscovery
-- ============================================================================
IF OBJECT_ID('[dbo].[DatabaseDiscovery]', 'U') IS NOT NULL
    DROP TABLE [dbo].[DatabaseDiscovery]
GO

CREATE TABLE [dbo].[DatabaseDiscovery] (
    [DiscoveryId] BIGINT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    [DiscoveryDate] DATETIME2(3) NOT NULL DEFAULT GETDATE(),
    [DatabaseName] SYSNAME NOT NULL,
    [DatabaseSizeMB] DECIMAL(18,2),
    [Status] VARCHAR(20) NOT NULL,
    [RecoveryModel] VARCHAR(20),
    [IsSystemDatabase] BIT DEFAULT 0,
    [AutoBackupApproved] BIT DEFAULT 0,
    [ApprovedBy] SYSNAME,
    [ApprovedDate] DATETIME2(3),
    [Notes] NVARCHAR(MAX),
    UNIQUE ([DiscoveryDate], [DatabaseName], [Status])
)
GO

CREATE INDEX IX_DatabaseDiscovery_Date ON [dbo].[DatabaseDiscovery]([DiscoveryDate] DESC)
CREATE INDEX IX_DatabaseDiscovery_Status ON [dbo].[DatabaseDiscovery]([Status])
GO

PRINT 'DatabaseDiscovery erstellt ✓'
GO

-- ============================================================================
-- TABLE 7: BackupConfiguration
-- ============================================================================
IF OBJECT_ID('[dbo].[BackupConfiguration]', 'U') IS NOT NULL
    DROP TABLE [dbo].[BackupConfiguration]
GO

CREATE TABLE [dbo].[BackupConfiguration] (
    [ConfigKey] VARCHAR(100) PRIMARY KEY,
    [ConfigValue] NVARCHAR(MAX) NOT NULL,
    [DataType] VARCHAR(20),
    [Description] NVARCHAR(MAX),
    [LastModifiedDate] DATETIME2(3) DEFAULT GETDATE(),
    [LastModifiedBy] SYSNAME DEFAULT SUSER_SNAME()
)
GO

-- FEHLER FIX: Datum-Konvertierung korrigiert
INSERT INTO [dbo].[BackupConfiguration] (ConfigKey, ConfigValue, DataType, Description)
VALUES
    ('TdpDir', 'C:\Program Files\Tivoli\TSM\TDPSql', 'STRING', 'TDP-Installationsverzeichnis'),
    ('SQLServer', @@SERVERNAME, 'STRING', 'SQL Server Instance'),
    ('FullBackupDay', 'Sunday', 'STRING', 'Wochentag für reguläre FULL-Backups'),
    ('BackupCheckIntervalMinutes', '1440', 'INT', 'Wie oft die Backup-Prüfung läuft'),
    ('RetentionDays', '90', 'INT', 'Wie lange BackupLog Einträge behalten werden'),
    ('AlertEmail', 'admin@bank.de', 'STRING', 'Email für Alerts bei Fehlern'),
    ('LastJsonSyncDate', CAST(GETDATE() AS VARCHAR(30)), 'DATETIME', 'Wann wurde JSON zuletzt synchronisiert?'),
    ('JsonConfigPath', 'C:\TDP-Backups\Config\BackupPlan.json', 'STRING', 'Pfad zur JSON-Konfigurationsdatei'),
    ('EnableAutoDiscovery', '1', 'BIT', 'Automatische Erkennung neuer Datenbanken?')
GO

PRINT 'BackupConfiguration erstellt ✓'
GO

-- ============================================================================
-- TRIGGERS
-- ============================================================================
PRINT ''
PRINT 'Schritt 2: Trigger erstellen...'
GO

-- FEHLER FIX: Trigger-Scope korrigiert (inserted/deleted)
IF OBJECT_ID('[dbo].[TR_TDP_BackupPlan_Audit]', 'TR') IS NOT NULL
    DROP TRIGGER [dbo].[TR_TDP_BackupPlan_Audit]
GO

CREATE TRIGGER [dbo].[TR_TDP_BackupPlan_Audit]
ON [dbo].[TDP_BackupPlan]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON

    -- INSERT: Neue DB in den Plan aufgenommen
    INSERT INTO [dbo].[TDP_BackupPlan_Audit]
    (DatabaseName, Action, NewEnabled, NewIncludeInDifferential, NewNotes, ChangedBy, AuditType)
    SELECT
        i.DatabaseName,
        'INSERT',
        i.Enabled,
        i.IncludeInDifferential,
        i.Notes,
        SUSER_SNAME(),
        'CONFIG'
    FROM inserted i
    WHERE NOT EXISTS (SELECT 1 FROM deleted d WHERE d.DatabaseName = i.DatabaseName)

    -- UPDATE: DB-Konfiguration geändert
    INSERT INTO [dbo].[TDP_BackupPlan_Audit]
    (DatabaseName, Action, OldEnabled, NewEnabled, OldIncludeInDifferential, NewIncludeInDifferential,
     OldNotes, NewNotes, ChangedBy, AuditType)
    SELECT
        i.DatabaseName,
        'UPDATE',
        d.Enabled,
        i.Enabled,
        d.IncludeInDifferential,
        i.IncludeInDifferential,
        d.Notes,
        i.Notes,
        SUSER_SNAME(),
        'CONFIG'
    FROM inserted i
    INNER JOIN deleted d ON i.DatabaseName = d.DatabaseName
    WHERE d.Enabled != i.Enabled
       OR d.IncludeInDifferential != i.IncludeInDifferential
       OR ISNULL(d.Notes, '') != ISNULL(i.Notes, '')

    -- DELETE: DB aus dem Plan entfernt
    INSERT INTO [dbo].[TDP_BackupPlan_Audit]
    (DatabaseName, Action, OldEnabled, OldIncludeInDifferential, OldNotes, ChangedBy, AuditType)
    SELECT
        d.DatabaseName,
        'DELETE',
        d.Enabled,
        d.IncludeInDifferential,
        d.Notes,
        SUSER_SNAME(),
        'CONFIG'
    FROM deleted d
    WHERE NOT EXISTS (SELECT 1 FROM inserted i WHERE i.DatabaseName = d.DatabaseName)
END
GO

PRINT 'TR_TDP_BackupPlan_Audit erstellt ✓'
GO

-- ============================================================================
-- STORED PROCEDURES
-- ============================================================================
PRINT ''
PRINT 'Schritt 3: Stored Procedures erstellen...'
GO

-- SP 1: Neue Datenbanken entdecken
IF OBJECT_ID('[dbo].[sp_DiscoverNewDatabases]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_DiscoverNewDatabases]
GO

CREATE PROCEDURE [dbo].[sp_DiscoverNewDatabases]
    @AutoApprove BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    -- Neue Datenbanken: in sys.databases aber nicht in BackupStatus
    INSERT INTO [dbo].[DatabaseDiscovery]
    (DiscoveryDate, DatabaseName, DatabaseSizeMB, Status, RecoveryModel, IsSystemDatabase)
    SELECT
        GETDATE(),
        d.name,
        (SELECT CAST(SUM(CAST(size AS BIGINT)) * 8.0 / 1024 AS DECIMAL(18,2)) FROM sys.master_files WHERE database_id = d.database_id),
        'NEW',
        d.recovery_model_desc,
        CASE WHEN d.database_id <= 4 THEN 1 ELSE 0 END
    FROM sys.databases d
    LEFT JOIN [dbo].[BackupStatus] bs ON d.name = bs.DatabaseName
    WHERE bs.DatabaseName IS NULL
      AND d.name NOT IN ('tempdb', 'model', 'msdb', 'master')
      AND d.state_desc = 'ONLINE'

    -- Entfernte Datenbanken: in BackupStatus aber nicht in sys.databases
    INSERT INTO [dbo].[DatabaseDiscovery]
    (DiscoveryDate, DatabaseName, Status, Notes)
    SELECT
        GETDATE(),
        bs.DatabaseName,
        'REMOVED',
        'Datenbank existiert nicht mehr auf dem Server'
    FROM [dbo].[BackupStatus] bs
    LEFT JOIN sys.databases d ON d.name = bs.DatabaseName
    WHERE d.name IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM [dbo].[DatabaseDiscovery] dd
        WHERE dd.DatabaseName = bs.DatabaseName AND dd.Status = 'REMOVED'
          AND DATEDIFF(DAY, dd.DiscoveryDate, GETDATE()) < 7
      )

    -- AutoApprove: Neue DBs automatisch hinzufügen
    IF @AutoApprove = 1
    BEGIN
        INSERT INTO [dbo].[TDP_BackupPlan] (DatabaseName, Enabled, IncludeInDifferential, Notes)
        SELECT
            dd.DatabaseName,
            1,
            1,
            'Auto: ' + FORMAT(dd.DiscoveryDate, 'yyyy-MM-dd HH:mm') + ', Size: ' + CAST(CAST(dd.DatabaseSizeMB AS INT) AS VARCHAR(20)) + ' MB'
        FROM [dbo].[DatabaseDiscovery] dd
        WHERE dd.Status = 'NEW'
          AND NOT EXISTS (SELECT 1 FROM [dbo].[TDP_BackupPlan] tp WHERE tp.DatabaseName = dd.DatabaseName)

        INSERT INTO [dbo].[BackupStatus] (DatabaseName, FullBackupExists, IsInBackupPlan, CreatedDate)
        SELECT
            dd.DatabaseName,
            0,
            1,
            GETDATE()
        FROM [dbo].[DatabaseDiscovery] dd
        WHERE dd.Status = 'NEW'
          AND NOT EXISTS (SELECT 1 FROM [dbo].[BackupStatus] bs WHERE bs.DatabaseName = dd.DatabaseName)

        UPDATE [dbo].[DatabaseDiscovery]
        SET Status = 'APPROVED', ApprovedBy = SUSER_SNAME(), ApprovedDate = GETDATE()
        WHERE Status = 'NEW' AND CAST(DiscoveryDate AS DATE) = CAST(GETDATE() AS DATE)
    END

    SELECT
        DatabaseName,
        DatabaseSizeMB,
        Status,
        RecoveryModel,
        DiscoveryDate
    FROM [dbo].[DatabaseDiscovery]
    WHERE Status IN ('NEW', 'REMOVED')
    ORDER BY DiscoveryDate DESC
END
GO

PRINT 'sp_DiscoverNewDatabases erstellt ✓'
GO

-- SP 2: BackupStatus aktualisieren
IF OBJECT_ID('[dbo].[sp_UpdateBackupStatus]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_UpdateBackupStatus]
GO

CREATE PROCEDURE [dbo].[sp_UpdateBackupStatus]
    @DatabaseName SYSNAME,
    @BackupType VARCHAR(20),
    @Status VARCHAR(20),
    @SizeMB DECIMAL(18,2) = NULL,
    @ErrorMessage NVARCHAR(MAX) = NULL,
    @BackupPath NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON

    IF NOT EXISTS (SELECT 1 FROM [dbo].[BackupStatus] WHERE DatabaseName = @DatabaseName)
    BEGIN
        INSERT INTO [dbo].[BackupStatus]
        (DatabaseName, FullBackupExists, CreatedDate, LastCheckedDate)
        VALUES (@DatabaseName, 0, GETDATE(), GETDATE())
    END

    IF @BackupType = 'FULL' AND @Status = 'SUCCESS'
    BEGIN
        UPDATE [dbo].[BackupStatus]
        SET
            FullBackupExists = 1,
            LastFullBackupDate = GETDATE(),
            LastFullBackupPath = @BackupPath,
            LastFullBackupStatus = 'SUCCESS',
            FullBackupSizeMB = @SizeMB,
            DifferentialAllowed = 1,
            ConsecutiveFailures = 0,
            LastErrorMessage = NULL,
            LastCheckedDate = GETDATE()
        WHERE DatabaseName = @DatabaseName
    END

    IF @BackupType = 'FULL' AND @Status = 'FAILED'
    BEGIN
        UPDATE [dbo].[BackupStatus]
        SET
            LastFullBackupStatus = 'FAILED',
            LastErrorMessage = @ErrorMessage,
            ConsecutiveFailures = ISNULL(ConsecutiveFailures, 0) + 1,
            LastCheckedDate = GETDATE()
        WHERE DatabaseName = @DatabaseName
    END

    IF @BackupType = 'DIFF' AND @Status = 'SUCCESS'
    BEGIN
        UPDATE [dbo].[BackupStatus]
        SET
            LastDifferentialDate = GETDATE(),
            ConsecutiveFailures = 0,
            LastErrorMessage = NULL,
            LastCheckedDate = GETDATE()
        WHERE DatabaseName = @DatabaseName
    END

    IF @BackupType = 'DIFF' AND @Status = 'FAILED'
    BEGIN
        UPDATE [dbo].[BackupStatus]
        SET
            LastErrorMessage = @ErrorMessage,
            ConsecutiveFailures = ISNULL(ConsecutiveFailures, 0) + 1,
            LastCheckedDate = GETDATE()
        WHERE DatabaseName = @DatabaseName
    END
END
GO

PRINT 'sp_UpdateBackupStatus erstellt ✓'
GO

-- SP 3: Backup-Eintrag in BackupLog erstellen
IF OBJECT_ID('[dbo].[sp_LogBackupResult]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_LogBackupResult]
GO

CREATE PROCEDURE [dbo].[sp_LogBackupResult]
    @DatabaseName SYSNAME,
    @BackupType VARCHAR(20),
    @Status VARCHAR(20),
    @StartTime DATETIME2(3),
    @EndTime DATETIME2(3),
    @SizeMB DECIMAL(18,2),
    @ErrorCode INT = NULL,
    @ErrorMessage NVARCHAR(MAX) = NULL,
    @BackupPath NVARCHAR(MAX) = NULL,
    @TdpJobId NVARCHAR(100) = NULL,
    @Notes NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @DurationSeconds INT = DATEDIFF(SECOND, @StartTime, @EndTime)
    DECLARE @LogId BIGINT

    INSERT INTO [dbo].[BackupLog]
    (ExecutionDate, DatabaseName, BackupType, Status, StartTime, EndTime, DurationSeconds,
     BackupSizeMB, BackupPath, ErrorCode, ErrorMessage, TdpJobId, Notes, ExecutedBy)
    VALUES
    (@EndTime, @DatabaseName, @BackupType, @Status, @StartTime, @EndTime, @DurationSeconds,
     @SizeMB, @BackupPath, @ErrorCode, @ErrorMessage, @TdpJobId, @Notes, SUSER_SNAME())

    SET @LogId = SCOPE_IDENTITY()

    IF @Status = 'FAILED' AND @ErrorMessage IS NOT NULL
    BEGIN
        DECLARE @Severity VARCHAR(20) = CASE
            WHEN @ErrorCode < 0 THEN 'CRITICAL'
            WHEN @ErrorCode < 100 THEN 'ERROR'
            ELSE 'WARNING'
        END

        INSERT INTO [dbo].[BackupLog_Errors]
        (LogId, DatabaseName, BackupType, ErrorCode, ErrorMessage, Severity)
        VALUES (@LogId, @DatabaseName, @BackupType, @ErrorCode, @ErrorMessage, @Severity)
    END

    RETURN @LogId
END
GO

PRINT 'sp_LogBackupResult erstellt ✓'
GO

-- SP 4: Status-Report
IF OBJECT_ID('[dbo].[sp_GetBackupStatusReport]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_GetBackupStatusReport]
GO

CREATE PROCEDURE [dbo].[sp_GetBackupStatusReport]
    @DatabaseName SYSNAME = NULL,
    @Days INT = 7
AS
BEGIN
    SET NOCOUNT ON

    SELECT
        bs.DatabaseName,
        bp.Enabled,
        bs.FullBackupExists,
        bs.LastFullBackupDate,
        bs.LastFullBackupStatus,
        bs.LastDifferentialDate,
        bs.ConsecutiveFailures,
        bs.FullBackupSizeMB,
        (SELECT COUNT(*) FROM [dbo].[BackupLog] bl
         WHERE bl.DatabaseName = bs.DatabaseName
           AND bl.ExecutionDate >= DATEADD(DAY, -@Days, GETDATE())) AS BackupCountLastDays,
        (SELECT COUNT(*) FROM [dbo].[BackupLog] bl
         WHERE bl.DatabaseName = bs.DatabaseName
           AND bl.Status = 'FAILED'
           AND bl.ExecutionDate >= DATEADD(DAY, -@Days, GETDATE())) AS FailedBackupsLastDays,
        bp.Notes
    FROM [dbo].[BackupStatus] bs
    LEFT JOIN [dbo].[TDP_BackupPlan] bp ON bs.DatabaseName = bp.DatabaseName
    WHERE (@DatabaseName IS NULL OR bs.DatabaseName = @DatabaseName)
    ORDER BY bs.DatabaseName

    SELECT TOP 50
        ble.ErrorId,
        ble.DatabaseName,
        ble.BackupType,
        ble.ErrorDate,
        ble.ErrorMessage,
        ble.Severity,
        ble.IsResolved
    FROM [dbo].[BackupLog_Errors] ble
    WHERE ble.ErrorDate >= DATEADD(DAY, -@Days, GETDATE())
      AND (@DatabaseName IS NULL OR ble.DatabaseName = @DatabaseName)
    ORDER BY ble.ErrorDate DESC
END
GO

PRINT 'sp_GetBackupStatusReport erstellt ✓'
GO

-- SP 5: Audit-Trail
IF OBJECT_ID('[dbo].[sp_GetAuditTrail]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_GetAuditTrail]
GO

CREATE PROCEDURE [dbo].[sp_GetAuditTrail]
    @DatabaseName SYSNAME = NULL,
    @Days INT = 90
AS
BEGIN
    SET NOCOUNT ON

    SELECT
        aa.AuditId,
        aa.DatabaseName,
        aa.Action,
        aa.OldEnabled,
        aa.NewEnabled,
        aa.OldIncludeInDifferential,
        aa.NewIncludeInDifferential,
        aa.OldNotes,
        aa.NewNotes,
        aa.ChangedBy,
        aa.ChangedDate,
        aa.Reason,
        aa.AuditType
    FROM [dbo].[TDP_BackupPlan_Audit] aa
    WHERE aa.ChangedDate >= DATEADD(DAY, -@Days, GETDATE())
      AND (@DatabaseName IS NULL OR aa.DatabaseName = @DatabaseName)
    ORDER BY aa.ChangedDate DESC
END
GO

PRINT 'sp_GetAuditTrail erstellt ✓'
GO

-- SP 6: Cleanup
IF OBJECT_ID('[dbo].[sp_CleanupOldLogs]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_CleanupOldLogs]
GO

CREATE PROCEDURE [dbo].[sp_CleanupOldLogs]
    @RetentionDays INT = 90
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @DeleteBefore DATETIME2(3) = DATEADD(DAY, -@RetentionDays, GETDATE())

    PRINT 'Lösche Logs älter als ' + CAST(@DeleteBefore AS VARCHAR(30))

    DELETE FROM [dbo].[BackupLog_Errors]
    WHERE ErrorDate < @DeleteBefore

    DELETE FROM [dbo].[BackupLog]
    WHERE ExecutionDate < @DeleteBefore

    DELETE FROM [dbo].[DatabaseDiscovery]
    WHERE DiscoveryDate < @DeleteBefore AND Status IN ('NEW', 'REMOVED')

    PRINT 'Cleanup abgeschlossen'
END
GO

PRINT 'sp_CleanupOldLogs erstellt ✓'
GO

-- ============================================================================
-- VIEWS
-- ============================================================================
PRINT ''
PRINT 'Schritt 4: Views erstellen...'
GO

IF OBJECT_ID('[dbo].[v_DatabasesWithoutFullBackup]', 'V') IS NOT NULL
    DROP VIEW [dbo].[v_DatabasesWithoutFullBackup]
GO

CREATE VIEW [dbo].[v_DatabasesWithoutFullBackup]
AS
SELECT
    bs.DatabaseName,
    bp.Enabled,
    bp.Notes,
    DATEDIFF(DAY, bs.CreatedDate, GETDATE()) AS DaysSinceAdded,
    bs.LastErrorMessage
FROM [dbo].[BackupStatus] bs
LEFT JOIN [dbo].[TDP_BackupPlan] bp ON bs.DatabaseName = bp.DatabaseName
WHERE bs.FullBackupExists = 0 AND bp.Enabled = 1
GO

PRINT 'v_DatabasesWithoutFullBackup erstellt ✓'
GO

IF OBJECT_ID('[dbo].[v_FailedBackups]', 'V') IS NOT NULL
    DROP VIEW [dbo].[v_FailedBackups]
GO

CREATE VIEW [dbo].[v_FailedBackups]
AS
SELECT TOP 100
    bl.DatabaseName,
    bl.BackupType,
    bl.Status,
    bl.ExecutionDate,
    bl.ErrorMessage,
    bl.DurationSeconds,
    CASE WHEN bl.ExecutionDate >= DATEADD(HOUR, -24, GETDATE()) THEN 'TODAY' ELSE 'OLDER' END AS TimeRange
FROM [dbo].[BackupLog] bl
WHERE bl.Status = 'FAILED'
  AND bl.ExecutionDate >= DATEADD(DAY, -30, GETDATE())
ORDER BY bl.ExecutionDate DESC
GO

PRINT 'v_FailedBackups erstellt ✓'
GO

-- ============================================================================
-- INITIALISIERUNG
-- ============================================================================
PRINT ''
PRINT 'Schritt 5: Initialisiere BackupStatus...'
GO

INSERT INTO [dbo].[BackupStatus] (DatabaseName, FullBackupExists, CreatedDate, IsInBackupPlan)
SELECT
    d.name,
    0,
    GETDATE(),
    CASE WHEN bp.DatabaseName IS NOT NULL THEN 1 ELSE 0 END
FROM sys.databases d
LEFT JOIN [dbo].[TDP_BackupPlan] bp ON d.name = bp.DatabaseName
WHERE d.name NOT IN ('tempdb', 'model', 'msdb', 'master')
  AND NOT EXISTS (SELECT 1 FROM [dbo].[BackupStatus] WHERE DatabaseName = d.name)
  AND d.state_desc = 'ONLINE'
GO

PRINT 'Initialisierung abgeschlossen ✓'
GO

-- ============================================================================
-- FINAL OUTPUT
-- ============================================================================
PRINT ''
PRINT '========== SETUP ERFOLGREICH =========='
PRINT 'Server: ' + @@SERVERNAME
PRINT 'Datum: ' + CAST(GETDATE() AS VARCHAR(30))
PRINT ''
PRINT 'Erstellte Objekte:'
PRINT '  ✓ 7 Tabellen'
PRINT '  ✓ 1 Trigger'
PRINT '  ✓ 6 Stored Procedures'
PRINT '  ✓ 2 Views'
PRINT ''
PRINT 'Verifikation:'
PRINT '  SELECT * FROM [master].[dbo].[TDP_BackupPlan]'
PRINT '  SELECT * FROM [master].[dbo].[BackupStatus]'
PRINT '  EXEC [master].[dbo].[sp_GetBackupStatusReport]'
PRINT ''
PRINT '========== READY =========='
GO
