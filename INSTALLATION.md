# TDP Backup System - Installationsanleitung (Bank-Standard)

**Version:** 1.0  
**Datum:** 2026-07-08  
**System:** Windows + SQL Server + TDP  

---

## 📋 Übersicht

Das TDP Backup System ersetzt das alte `backup_all_full.cmd` mit einer modernen, wartbaren Lösung:

```
┌─────────────────────────────────────────────────────────────┐
│ SQL Server Agent (täglich 20:00 Uhr)                        │
└──────────────────────┬──────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────┐
│ Batch: Backup_TdpFull.cmd (Wrapper)                         │
│ Pfad: C:\Program Files\Tivoli\TSM\TDPSql\01_Backup_CMD\     │
└──────────────────────┬──────────────────────────────────────┘
                       ↓ (PowerShell aufrufen)
┌─────────────────────────────────────────────────────────────┐
│ PowerShell: Backup-TdpFull.ps1 (Orchestration)              │
│ + ConfigLoader.psm1 (JSON laden)                            │
│ + SqlTracking.psm1 (SQL-Updates)                            │
│ + TdpBackupHelper.psm1 (TDP-Befehle)                        │
└──────────────────────┬──────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────┐
│ SQL Server [master]                                         │
│ - TDP_BackupPlan (Konfiguration)                            │
│ - BackupStatus (Status pro DB)                              │
│ - BackupLog (Alle Backup-Runs)                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Installation (5 Schritte)

### **Schritt 1: Dateien auf Server kopieren**

```powershell
# GitHub klonen oder Dateien kopieren
cd "C:\Program Files\Tivoli\TSM\TDPSql"

# TDP-Backup-System kopieren
Copy-Item -Path "\\<GitHub-Path>\SQL-Tools\TDP-Backup\*" `
          -Destination ".\TDP-Backup-System" -Recurse

# Backup_TdpFull.cmd in richtiges Verzeichnis
Copy-Item -Path ".\TDP-Backup-System\01_Backup_CMD\Backup_TdpFull.cmd" `
          -Destination ".\01_Backup_CMD\" -Force
```

**Resultat:**
```
C:\Program Files\Tivoli\TSM\TDPSql\
├── 01_Backup_CMD\
│   └── Backup_TdpFull.cmd        ← Neuer Wrapper
├── 03_Log\                        ← Logs gehen hier hin
├── TDP-Backup-System\
│   ├── Backup-TdpFull.ps1        ← Hauptskript
│   ├── Configure-BackupPlan.ps1  ← GUI
│   ├── BackupPlan.json           ← MUSS hier sein!
│   └── Modules\
│       ├── ConfigLoader.psm1
│       ├── SqlTracking.psm1
│       └── TdpBackupHelper.psm1
```

---

### **Schritt 2: SQL-Tracking-Tabellen erstellen**

```powershell
# Auf YOUR-SQL-SERVER als Admin ausführen:
sqlcmd -S YOUR-SQL-SERVER -i "C:\Program Files\Tivoli\TSM\TDPSql\TDP-Backup-System\01_TDP_BackupTracking_Setup.sql"

# Verifikation:
sqlcmd -S YOUR-SQL-SERVER -Q "SELECT COUNT(*) AS [Tables] FROM [master].[INFORMATION_SCHEMA].[TABLES] WHERE [TABLE_NAME] LIKE 'TDP_%' OR [TABLE_NAME] LIKE 'Backup%'"
```

**Erwartet:** ~7 Tabellen

---

### **Schritt 3: JSON-Konfiguration anpassen**

**Datei:** `C:\Program Files\Tivoli\TSM\TDPSql\BackupPlan.json`

```json
{
  "Configuration": {
    "TdpDir": "C:\\Program Files\\Tivoli\\TSM\\TDPSql",
    "SQLServer": "YOUR-SQL-SERVER",
    "TSMPassword": "***DEIN-PASSWORD***",      ← Anpassen!
    "TsmOptFile": "C:\\Program Files\\Tivoli\\TSM\\TDPSql\\dsm.opt",
    "TdpConfigFile": "C:\\Program Files\\Tivoli\\TSM\\TDPSql\\tdpsql.cfg",
    "LogPath": "C:\\Program Files\\Tivoli\\TSM\\TDPSql\\03_Log",
    "AlertEmail": "backup-admin@yourbank.de"    ← Anpassen!
  },
  "SelectedDatabases": [
    {
      "Name": "AdventureWorks",
      "Enabled": true,
      "Priority": 100,
      "Notes": "Production"
    }
  ]
}
```

**⚠️ WICHTIG:** Passwort verschlüsseln (optional, aber sicher):

```powershell
# Verschlüsseltes Passwort generieren
$password = Read-Host "TSM-Passwort eingeben" -AsSecureString
$encrypted = ConvertFrom-SecureString $password
Write-Host "Kopiere diesen String in BackupPlan.json:"
Write-Host $encrypted
```

---

### **Schritt 4: PowerShell Execution Policy (einmalig)**

```powershell
# Als Admin ausführen:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force

# Verifikation:
Get-ExecutionPolicy
```

**Erwartet:** `RemoteSigned`

---

### **Schritt 5: SQL Agent Job erstellen**

```powershell
# Auf YOUR-SQL-SERVER als Admin ausführen:
sqlcmd -S YOUR-SQL-SERVER -i "C:\Program Files\Tivoli\TSM\TDPSql\TDP-Backup-System\02_Create_Agent_Job.sql"
```

**Verifikation in SQL Server Management Studio:**
- SQL Server Agent → Jobs
- Job: `TDP_Backup_Daily`
- Schedule: `Daily_20_00` (täglich 20:00)
- Status: **Enabled**

---

## 🧪 Test

### **Manuell testen (vor erstem Produktiueinsatz)**

```powershell
# PowerShell als Admin
cd "C:\Program Files\Tivoli\TSM\TDPSql\TDP-Backup-System"

# Direkter Test
.\Backup-TdpFull.ps1 -SqlServer YOUR-SQL-SERVER

# Oder über Batch-Wrapper (wie Agent aufruft)
cd "C:\Program Files\Tivoli\TSM\TDPSql\01_Backup_CMD"
.\Backup_TdpFull.cmd
```

### **Logs prüfen**

```powershell
# Neueste Logs anschauen
Get-ChildItem "C:\Program Files\Tivoli\TSM\TDPSql\03_Log\Backup_TdpFull_*.log" | 
  Sort-Object LastWriteTime -Descending | 
  Select-Object -First 1 | 
  Get-Content -Tail 50

# SQL-Logs
sqlcmd -S YOUR-SQL-SERVER -Q "SELECT TOP 20 * FROM [master].[dbo].[BackupLog] ORDER BY [ExecutionDate] DESC"
```

### **Status-Report**

```powershell
sqlcmd -S YOUR-SQL-SERVER -Q "EXEC [master].[dbo].[sp_GetBackupStatusReport]"
```

---

## 🎨 GUI Konfiguration (Kunde)

**Statt JSON direkt zu editieren:**

```powershell
C:\Program Files\Tivoli\TSM\TDPSql\TDP-Backup-System\Configure-BackupPlan.ps1
```

Die GUI ermöglicht:
- ✅ Datenbanken hinzufügen/entfernen
- ✅ Enabled/Disabled einstellen
- ✅ Priorität setzen
- ✅ Notizen hinzufügen
- ✅ Speichern (schreibt JSON automatisch)

---

## 🔄 Täglicher Workflow

**20:00 Uhr - SQL Agent startet:**

1. Agent ruft `Backup_TdpFull.cmd` auf
2. Batch-Wrapper startet PowerShell
3. PowerShell lädt `BackupPlan.json`
4. Synchronisiert zu SQL `[TDP_BackupPlan]` Tabelle
5. **Sonderbehandlung:** DBs ohne FULL → sofort FULL (egal welcher Tag)
6. **Sonntag:** Alle DBs FULL
7. **Mo-Sa:** DIFF (nur wenn FULL existiert)
8. Updates `[BackupStatus]`, `[BackupLog]`, `[BackupLog_Errors]`
9. Log-Datei: `C:\Program Files\Tivoli\TSM\TDPSql\03_Log\Backup_TdpFull_20260708_200000.log`

---

## 📊 Monitoring

### **Dashboard (SQL Queries)**

```sql
-- Status heute
EXEC [master].[dbo].[sp_GetBackupStatusReport]

-- Fehler
SELECT TOP 50 * FROM [master].[dbo].[v_FailedBackups]

-- DBs ohne FULL
SELECT * FROM [master].[dbo].[v_DatabasesWithoutFullBackup]

-- Audit-Trail (wer hat was geändert)
EXEC [master].[dbo].[sp_GetAuditTrail] @DatabaseName = NULL, @Days = 30
```

### **Automatische Alerts (Optional)**

```sql
-- Alert erstellen: Wenn Backup fehlgeschlagen
CREATE ALERT [TDP_Backup_Failed]
  ON EVENT 'TDP_Backup_Failed'
  WITH SEVERITY = 16
  RESPONSE JOB_ID = '<JobID>'
```

---

## 🚨 Fehlerbehebung

| Problem | Ursache | Lösung |
|---------|--------|--------|
| Agent-Job schlägt fehl | `Backup_TdpFull.cmd` nicht gefunden | Pfad prüfen: `C:\Program Files\Tivoli\TSM\TDPSql\01_Backup_CMD\` |
| "PowerShell not found" | PS nicht im System PATH | `Set-ExecutionPolicy RemoteSigned` + Neustarten |
| JSON-Fehler | Syntax-Fehler in BackupPlan.json | JSON in https://jsonlint.com/ validieren |
| SQL-Verbindung fehlgeschlagen | SQL Server offline oder wrong credentials | `sqlcmd -S YOUR-SQL-SERVER -Q "SELECT @@VERSION"` testen |
| DIFF-Backups fehlgeschlagen | Keine FULL vorhanden | Warten auf nächste Nacht (Sonderbehandlung läuft) |
| Logs verschwunden | 90-Tage-Cleanup läuft | `sp_CleanupOldLogs @RetentionDays=90` anpassen |

---

## 🔐 Sicherheit

- ✅ **TSM-Passwort verschlüsselt** in Batch-Umgebung
- ✅ **xp_cmdshell nicht nötig** (Bank-Policy OK)
- ✅ **Audit-Trail** für alle Änderungen
- ✅ **Fehler-Isolation** (eine DB-Fehler stoppt nicht alles)
- ✅ **Logs mit Compliance** (2+ Jahre Audit-Trail)

---

## 📞 Support

**GitHub:**  
https://github.com/JankeUwe/TDPBackup

**Fragen?**
1. README.md lesen
2. Logs prüfen (`C:\Program Files\Tivoli\TSM\TDPSql\03_Log\`)
3. SQL-Reports laufen (`sp_GetBackupStatusReport`)

---

**Erfolg! Das System ist bereit für Production.** 🚀
