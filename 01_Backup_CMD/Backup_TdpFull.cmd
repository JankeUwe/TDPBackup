@echo off
REM ==============================================================================
REM Backup_TdpFull.cmd - Wrapper für PowerShell TDP Backup-Orchestration
REM Replacement für backup_all_full.cmd
REM Vom SQL-Agent aufgerufen (genau wie bisher)
REM ==============================================================================
REM VERWENDUNG (im SQL-Agent):
REM   C:\Program Files\Tivoli\TSM\TDPSql\01_Backup_CMD\Backup_TdpFull.cmd
REM ==============================================================================

setlocal enabledelayedexpansion

REM Pfade
SET TdpDir=C:\Program Files\Tivoli\TSM\TDPSql
SET BackupScriptsDir=%TdpDir%\..\..\..\SQL-Tools\TDP-Backup
SET ConfigPath=%TdpDir%\BackupPlan.json
SET LogPath=%TdpDir%\03_Log
SET LogFile=%LogPath%\Backup_TdpFull_%DATE:~10,4%%DATE:~4,2%%DATE:~7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.log

REM SQL Server Instance
SET SQLServer=SRPSDSQL011

echo. >> %LogFile%
echo ============================================================================== >> %LogFile%
echo TDP Backup - Started >> %LogFile%
echo Date: %DATE% %TIME% >> %LogFile%
echo PowerShell Script: %BackupScriptsDir%\Backup-TdpFull.ps1 >> %LogFile%
echo Config: %ConfigPath% >> %LogFile%
echo ============================================================================== >> %LogFile%
echo. >> %LogFile%

REM Log-Verzeichnis erstellen (falls nicht vorhanden)
if not exist "%LogPath%" mkdir "%LogPath%"

REM PowerShell ausführen
REM -NoProfile: Keine Profile laden (schneller, sauberer)
REM -ExecutionPolicy Bypass: Ausführungsrichtlinie umgehen
REM -File: Skript-Datei ausführen
REM -ConfigPath: Pfad zur JSON-Config
REM -SqlServer: SQL Server Instance

powershell.exe -NoProfile -ExecutionPolicy Bypass ^
  -Command "try { & '%BackupScriptsDir%\Backup-TdpFull.ps1' -ConfigPath '%ConfigPath%' -SqlServer '%SQLServer%' } catch { Write-Error $_.Exception.Message; exit 1 }" ^
  >> %LogFile% 2>&1

SET PowerShellExitCode=%ERRORLEVEL%

echo. >> %LogFile%
echo ============================================================================== >> %LogFile%
if %PowerShellExitCode% EQU 0 (
  echo ✓ TDP Backup COMPLETED SUCCESSFULLY >> %LogFile%
  echo ExitCode: %PowerShellExitCode% >> %LogFile%
) else (
  echo ✗ TDP Backup FAILED >> %LogFile%
  echo ExitCode: %PowerShellExitCode% >> %LogFile%
)
echo Date: %DATE% %TIME% >> %LogFile%
echo ============================================================================== >> %LogFile%
echo. >> %LogFile%

REM Exit-Code an SQL-Agent zurückgeben
exit /b %PowerShellExitCode%
