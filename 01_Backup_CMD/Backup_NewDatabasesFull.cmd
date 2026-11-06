@echo off
REM ==============================================================================
REM Backup_NewDatabasesFull.cmd - FULL fuer Datenbanken ohne Differential-Basis
REM
REM Als erster Step in den bestehenden Jobs (Diff und TLog) einhaengen. Die
REM bestehenden cmd-Dateien mit "backup * difffull" / "backup * log" bleiben
REM unveraendert. Backup-TdpNewDatabases.ps1 muss im selben Ordner liegen.
REM ==============================================================================

REM Instanzname wie bei /SQLSERVer= in den bestehenden cmd-Dateien
SET SqlInstance=YOUR-SQL-INSTANCE
SET TdpDir=C:\progra~1\Tivoli\TSM\TDPSql

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Backup-TdpNewDatabases.ps1" -SqlInstance "%SqlInstance%" -TdpDir "%TdpDir%"

exit /b %ERRORLEVEL%
