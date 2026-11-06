-- ==============================================================================
-- 03_Add_NewDatabases_Step.sql
-- Haengt den Step "NewDatabases_Full" als ERSTEN Step in einen bestehenden Agent-Job
-- (z.B. den Diff-Job und den TLog-Job). Der vorhandene Step mit "backup * difffull"
-- bzw. "backup * log" bleibt unveraendert und wird danach ausgefuehrt.
--
-- Voraussetzung: Backup_NewDatabasesFull.cmd und Backup-TdpNewDatabases.ps1 liegen
-- im Ordner 01_Backup_CMD, in Backup_NewDatabasesFull.cmd ist SqlInstance gesetzt.
--
-- Je Job einmal ausfuehren (@job_name anpassen). Mehrfaches Ausfuehren ist harmlos.
-- Entfernen: EXEC msdb.dbo.sp_delete_jobstep @job_name = N'<Job>', @step_id = 1
-- ==============================================================================
USE [msdb]
GO

DECLARE @job_name  SYSNAME       = N'YOUR-DIFF-JOB-NAME'   -- anpassen
DECLARE @step_name SYSNAME       = N'NewDatabases_Full'
DECLARE @command   NVARCHAR(MAX) = N'"C:\Program Files\Tivoli\TSM\TDPSql\01_Backup_CMD\Backup_NewDatabasesFull.cmd"'

IF NOT EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = @job_name)
BEGIN
    RAISERROR('Job [%s] nicht gefunden - @job_name anpassen.', 16, 1, @job_name)
    RETURN
END

IF EXISTS (SELECT 1 FROM dbo.sysjobsteps js JOIN dbo.sysjobs j ON j.job_id = js.job_id
           WHERE j.name = @job_name AND js.step_name = @step_name)
BEGIN
    PRINT 'Step [' + @step_name + '] existiert in Job [' + @job_name + '] bereits - nichts zu tun.'
    RETURN
END

-- on_success/on_fail = 3: weiter mit dem naechsten Step. Das Diff-/Log-Backup laeuft also
-- auch dann, wenn das FULL einer neuen Datenbank scheitert. Der Fehlschlag steht dann im
-- Job-Verlauf beim Step (Job-Gesamtergebnis richtet sich nach dem letzten Step).
EXEC dbo.sp_add_jobstep
    @job_name          = @job_name,
    @step_id           = 1,
    @step_name         = @step_name,
    @subsystem         = N'CmdExec',
    @command           = @command,
    @on_success_action = 3,
    @on_fail_action    = 3

-- Startschritt muss der neue Step 1 sein
DECLARE @job_id UNIQUEIDENTIFIER = (SELECT job_id FROM dbo.sysjobs WHERE name = @job_name)
EXEC dbo.sp_update_job @job_id = @job_id, @start_step_id = 1

SELECT j.name AS JobName, js.step_id, js.step_name, js.subsystem, js.on_success_action, js.on_fail_action, js.command
FROM dbo.sysjobsteps js JOIN dbo.sysjobs j ON j.job_id = js.job_id
WHERE j.name = @job_name
ORDER BY js.step_id
GO
