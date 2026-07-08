-- ==============================================================================
-- 02_Create_Agent_Job.sql - SQL Agent Job für TDP Backup-Orchestration
-- ==============================================================================
-- Erstellt einen SQL Server Agent Job, der täglich um 20:00 Uhr das
-- PowerShell-Backup-Skript über ein Batch-Wrapper aufruft
--
-- WICHTIG: xp_cmdshell ist NICHT erforderlich!
-- Der Job ruft nur eine CMD-Datei auf, genau wie bisher.
--
-- USAGE:
--   sqlcmd -S SRPSDSQL011 -i "02_Create_Agent_Job.sql"
-- ==============================================================================

USE [msdb]
GO

PRINT '========== TDP Backup - SQL Agent Job Setup =========='
PRINT 'Server: ' + @@SERVERNAME
PRINT ''

-- ==============================================================================
-- 1. Job erstellen (oder aktualisieren falls vorhanden)
-- ==============================================================================

PRINT 'Step 1: Erstelle/aktualisiere Job [TDP_Backup_Daily]...'

-- Existierenden Job löschen falls vorhanden
IF EXISTS (SELECT 1 FROM [msdb].[dbo].[sysjobs] WHERE [name] = 'TDP_Backup_Daily')
BEGIN
    EXEC [msdb].[dbo].[sp_delete_job] @job_name = 'TDP_Backup_Daily', @delete_unused_schedule = 1
    PRINT '  ✓ Alter Job gelöscht'
END

-- Neuen Job erstellen
DECLARE @job_id UNIQUEIDENTIFIER
EXEC [msdb].[dbo].[sp_add_job]
    @job_name = 'TDP_Backup_Daily',
    @enabled = 1,
    @start_step_name = 'Execute_TdpFull_Backup',
    @category_name = 'Database Maintenance',
    @owner_login_name = 'sa',
    @description = 'TDP Backup - Täglich 20:00 Uhr (FULL + DIFF)',
    @job_id = @job_id OUTPUT

PRINT '  ✓ Job erstellt: [TDP_Backup_Daily]'

-- ==============================================================================
-- 2. Job-Step erstellen: PowerShell via Batch-Wrapper
-- ==============================================================================

PRINT 'Step 2: Erstelle Job-Step [Execute_TdpFull_Backup]...'

EXEC [msdb].[dbo].[sp_add_jobstep]
    @job_name = 'TDP_Backup_Daily',
    @step_name = 'Execute_TdpFull_Backup',
    @step_id = 1,
    @subsystem = 'CmdExec',  -- Batch-Ausführung (NICHT PowerShell!)
    @command = 'C:\Program Files\Tivoli\TSM\TDPSql\01_Backup_CMD\Backup_TdpFull.cmd',
    @retry_attempts = 2,      -- 2x retry bei Fehler
    @retry_interval = 1,      -- 1 Minute warten
    @on_success_action = 1,   -- Gehe zum nächsten Step / Job erfolgreich
    @on_fail_action = 2       -- Job fehlgeschlagen

PRINT '  ✓ Job-Step erstellt'
PRINT '    Command: C:\Program Files\Tivoli\TSM\TDPSql\01_Backup_CMD\Backup_TdpFull.cmd'

-- ==============================================================================
-- 3. Zeitplan erstellen: Täglich 20:00 Uhr
-- ==============================================================================

PRINT 'Step 3: Erstelle Zeitplan [Daily_20_00]...'

-- Existierenden Schedule löschen falls vorhanden
IF EXISTS (SELECT 1 FROM [msdb].[dbo].[sysschedules] WHERE [name] = 'Daily_20_00')
BEGIN
    EXEC [msdb].[dbo].[sp_detach_schedule] @job_name = 'TDP_Backup_Daily', @schedule_name = 'Daily_20_00'
    EXEC [msdb].[dbo].[sp_delete_schedule] @schedule_name = 'Daily_20_00'
    PRINT '  ✓ Alter Schedule gelöscht'
END

-- Neuen Schedule erstellen
DECLARE @schedule_id INT
EXEC [msdb].[dbo].[sp_add_schedule]
    @schedule_name = 'Daily_20_00',
    @freq_type = 4,           -- Täglich
    @freq_interval = 1,       -- Jeden Tag
    @active_start_time = 200000,  -- 20:00:00
    @schedule_id = @schedule_id OUTPUT

PRINT '  ✓ Schedule erstellt: Täglich 20:00 Uhr'

-- ==============================================================================
-- 4. Schedule an Job binden
-- ==============================================================================

PRINT 'Step 4: Binde Schedule an Job...'

EXEC [msdb].[dbo].[sp_attach_schedule]
    @job_name = 'TDP_Backup_Daily',
    @schedule_name = 'Daily_20_00'

PRINT '  ✓ Schedule gebunden'

-- ==============================================================================
-- 5. Server an Job binden (für Multi-Server)
-- ==============================================================================

PRINT 'Step 5: Server-Bindung...'

EXEC [msdb].[dbo].[sp_add_jobserver]
    @job_name = 'TDP_Backup_Daily',
    @server_name = N'(local)'

PRINT '  ✓ Job an lokalen Server gebunden'

-- ==============================================================================
-- VERIFIKATION
-- ==============================================================================

PRINT ''
PRINT '========== VERIFIKATION =========='
PRINT ''

SELECT
    'Job Info' AS [Type],
    [name] AS [JobName],
    CASE WHEN [enabled] = 1 THEN 'Enabled' ELSE 'DISABLED' END AS [Status],
    [description] AS [Description]
FROM [msdb].[dbo].[sysjobs]
WHERE [name] = 'TDP_Backup_Daily'

SELECT
    'Job Step' AS [Type],
    [step_name] AS [StepName],
    [subsystem] AS [Subsystem],
    [command] AS [Command],
    CASE WHEN [retry_attempts] > 0 THEN CAST([retry_attempts] AS VARCHAR(2)) + 'x' ELSE 'No Retry' END AS [Retry]
FROM [msdb].[dbo].[sysjobsteps]
WHERE [job_id] = (SELECT [job_id] FROM [msdb].[dbo].[sysjobs] WHERE [name] = 'TDP_Backup_Daily')

SELECT
    'Schedule' AS [Type],
    s.[name] AS [ScheduleName],
    CASE
        WHEN s.[freq_type] = 4 THEN 'Daily'
        WHEN s.[freq_type] = 8 THEN 'Weekly'
        WHEN s.[freq_type] = 16 THEN 'Monthly'
        ELSE 'Other'
    END AS [Frequency],
    CONVERT(VARCHAR(8), s.[active_start_time], 108) AS [StartTime]
FROM [msdb].[dbo].[sysjobschedules] js
JOIN [msdb].[dbo].[sysschedules] s ON js.[schedule_id] = s.[schedule_id]
WHERE js.[job_id] = (SELECT [job_id] FROM [msdb].[dbo].[sysjobs] WHERE [name] = 'TDP_Backup_Daily')

PRINT ''
PRINT '========== SETUP ERFOLGREICH =========='
PRINT ''
PRINT 'Job läuft täglich um 20:00 Uhr'
PRINT 'Logs: C:\Program Files\Tivoli\TSM\TDPSql\03_Log\Backup_TdpFull_*.log'
PRINT ''
PRINT 'Manueller Test:'
PRINT '  EXEC msdb.dbo.sp_start_job @job_name = ''TDP_Backup_Daily'''
PRINT ''

GO
