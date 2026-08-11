# TDP Backup Tracking System

Intelligentes Backup-Management für SQL Server mit TDP (Tivoli Data Protection).

## 📋 Features

- ✅ **Flexible DB-Selection** — JSON-basierte Konfiguration
- ✅ **Automatische Sonderbehandlung** — Neue DBs ohne FULL → sofort FULL
- ✅ **Audit-Trail** — Alle Änderungen werden geloggt (Bank-Compliance)
- ✅ **Fehlertoleranz** — DIFF-Fehler verhindern, wenn kein FULL vorhanden
- ✅ **Multi-Server** — Läuft auf allen SQL Server Instanzen

---

## 🚀 Quick Start

### 1. Setup durchführen

```powershell
# SQL-Tracking-Tabellen auf <SQLInstance> erstellen
sqlcmd -S <SQLInstance> -i "C:\CCM\SQL-Tools\TDP-Backup\01_TDP_BackupTracking_Setup.sql"

# Gleiches für weitere Server (falls vorhanden)
sqlcmd -S <SQLInstance2> -i "C:\CCM\SQL-Tools\TDP-Backup\01_TDP_BackupTracking_Setup.sql"
```

### 2. JSON-Konfiguration anpassen

Datei: `C:\TDP-Backups\Config\BackupPlan.json`

```json
{
  "Configuration": {
    "TdpDir": "C:\\Program Files\\Tivoli\\TSM\\TDPSql",
    "SQLServer": "<SQLInstance>",
    "TSMPassword": "***dein-passwort***",
    "AlertEmail": "admin@example.com"
  },
  "SelectedDatabases": [
    {
      "Name": "AdventureWorks",
      "Enabled": true,
      "Priority": 100,
      "Notes": "Production database"
    },
    {
      "Name": "MyAppDB",
      "Enabled": true,
      "Priority": 50
    }
  ]
}
```

**Wichtig:** 
- `TSMPassword` sollte verschlüsselt sein (optional: PowerShell SecureString verwenden)
- Nur Datenbanken in `SelectedDatabases` werden gesichert
- `Enabled: false` = Datenbank wird nicht gesichert

### 3. Agent-Job in SQL Server erstellen

```sql
USE msdb
GO

CREATE JOB [TDP_Backup_Daily] AS
    EXEC xp_cmdshell 'powershell -ExecutionPolicy Bypass -File "C:\CCM\SQL-Tools\TDP-Backup\Backup-TdpFull.ps1"'
GO

-- Täglich um 20:00 Uhr ausführen
CREATE SCHEDULE [Daily_20_00] 
    FREQ_TYPE=4 (Daily)
    FREQ_INTERVAL=1
    ACTIVE_START_TIME=200000
GO

ATTACH_SCHEDULE [TDP_Backup_Daily], [Daily_20_00]
GO
```

### 4. Testen

```powershell
# Skript manuell ausführen (für Tests)
cd C:\CCM\SQL-Tools\TDP-Backup
.\Backup-TdpFull.ps1
# Die SQL-Instance kommt aus TdpBackup.config (per Setup-TdpBackup.ps1 konfiguriert)

# Logs anschauen
dir C:\TDP-Backups\Logs\
```

---

## 📊 Workflow (täglich um 20:00 Uhr)

```
┌─────────────────────────────────────────────────────────┐
│ 1. JSON laden & zu SQL synchronisieren                  │
│    (BackupPlan.json → [TDP_BackupPlan])                 │
└──────────────────────────────────┬──────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────┐
│ 2. Sonderbehandlung:                                    │
│    DBs ohne FULL-Backup → sofort FULL (egal welcher Tag)│
│    (unabhängig vom Wochentag!)                          │
└──────────────────────────────────┬──────────────────────┘
                                   ↓
                        ┌──────────────────────┐
                        │ Welcher Wochentag?   │
                        └──────┬───────────────┘
                               │
                    ┌──────────┴──────────┐
                    ↓                     ↓
            ┌────────────────┐   ┌──────────────────┐
            │    SONNTAG     │   │   MONTAG-SAMSTAG │
            │ FULL-Backups   │   │ DIFF-Backups     │
            │ (alle DBs)     │   │ (nur mit FULL)   │
            └────────────────┘   └──────────────────┘
                    ↓                     ↓
            ┌────────────────────────────────────────┐
            │ 3. SQL-Tabellen aktualisieren:          │
            │    - BackupStatus (FULL-Status)        │
            │    - BackupLog (Log-Eintrag)           │
            │    - BackupLog_Errors (wenn Fehler)    │
            └────────────────────────────────────────┘
                              ↓
            ┌────────────────────────────────────────┐
            │ 4. Audit-Trail speichern:              │
            │    (TDP_BackupPlan_Audit)              │
            │    Wer hat was wann geändert?          │
            └────────────────────────────────────────┘
```

---

## 📁 Dateistruktur

```
C:\CCM\SQL-Tools\TDP-Backup\
├── 01_TDP_BackupTracking_Setup.sql      # SQL-Setup (einmalig)
├── Backup-TdpFull.ps1                  # Hauptskript (täglich)
├── BackupPlan.json                     # Konfiguration (Kunde editiert)
├── README.md                           # Diese Datei
└── Modules/
    ├── ConfigLoader.psm1               # JSON laden & SQL-Sync
    ├── SqlTracking.psm1                # SQL-Abfragen
    └── TdpBackupHelper.psm1            # TDP-Befehle ausführen

C:\TDP-Backups\
├── Config/
│   ├── BackupPlan.json                 # Zentrale Konfiguration
│   ├── dsm.opt                         # TDP-Konfiguration
│   └── tdpsql.cfg                      # TDP-SQL-Konfiguration
└── Logs/
    ├── backup_FULL_AdventureWorks_*.log
    ├── backup_DIFF_MyAppDB_*.log
    └── ...
```

---

## 🔍 Monitoring & Reports

### Status abfragen (SQL)

```sql
-- Welche DBs haben FULL-Backup?
SELECT DatabaseName, LastFullBackupDate, FullBackupExists
FROM [master].[dbo].[BackupStatus]
ORDER BY LastFullBackupDate DESC

-- Fehlgeschlagene Backups (letzte 7 Tage)
SELECT TOP 20
    DatabaseName, BackupType, Status, ErrorMessage, ExecutionDate
FROM [master].[dbo].[BackupLog]
WHERE Status = 'FAILED'
  AND ExecutionDate >= DATEADD(DAY, -7, GETDATE())
ORDER BY ExecutionDate DESC

-- Audit-Trail (wer hat was geändert?)
EXEC [master].[dbo].[sp_GetAuditTrail] @DatabaseName = NULL, @Days = 90

-- Status-Report
EXEC [master].[dbo].[sp_GetBackupStatusReport]
```

### Neue Datenbanken erkennen

```sql
-- Neue DBs, die noch nicht im Backup-Plan sind
SELECT * FROM [master].[dbo].[v_DatabasesWithoutFullBackup]

-- Automatisch erkannte neue DBs
SELECT DiscoveryId, DatabaseName, Status, DiscoveryDate
FROM [master].[dbo].[DatabaseDiscovery]
WHERE Status = 'NEW'
ORDER BY DiscoveryDate DESC
```

---

## ⚙️ Konfiguration anpassen

### Datenbank hinzufügen

**Option 1: JSON editieren (einfach)**
```json
"SelectedDatabases": [
  {
    "Name": "MeineNeueDatei",
    "Enabled": true,
    "Priority": 75,
    "Notes": "Neue Datenbank"
  }
]
```

**Option 2: SQL direkta (für DBAs)**
```sql
INSERT INTO [master].[dbo].[TDP_BackupPlan]
(DatabaseName, Enabled, IncludeInDifferential, Priority, Notes)
VALUES ('MeineNeueDatei', 1, 1, 75, 'Neue Datenbank')
```

### Datenbank deaktivieren

**JSON:**
```json
"Enabled": false   -- Datenbank wird nicht mehr gesichert
```

**SQL:**
```sql
UPDATE [master].[dbo].[TDP_BackupPlan]
SET Enabled = 0
WHERE DatabaseName = 'MyAppDB'
```

---

## 🚨 Fehlerbehandlung

| Fehler | Ursache | Lösung |
|--------|--------|--------|
| DIFF-Backup schlägt fehl | Keine FULL vorhanden | Warten bis Sonderbehandlung FULL durchführt (nächste Nacht) |
| TDP-Dienst nicht erreichbar | TDP offline | `sqlcmd -S <SQLInstance> -Q "EXEC xp_cmdshell 'C:\...\tdpsqlc.exe -?'"` |
| JSON-Fehler beim Laden | JSON-Syntax ungültig | JSON in https://jsonlint.com/ validieren |
| SQL-Verbindung fehlgeschlagen | SQL Server offline | Connectivity checken: `sqlcmd -S <SQLInstance> -Q "SELECT @@VERSION"` |

---

## 📅 Zeitplan (Bank-Standard)

```
Sonntag 20:00  → FULL-Backups (alle Datenbanken mit Enabled=1)
Montag 20:00   → DIFF-Backups (nur DBs mit FullBackupExists=1)
...
Samstag 20:00  → DIFF-Backups

JEDERZEIT:     → Sonderbehandlung (DBs ohne FULL → sofort FULL)
```

---

## 🔐 Security Notes

1. **TSMPassword** — wird von `Setup-TdpBackup.ps1` als `SecureString` (Windows-DPAPI, benutzer-/maschinengebunden) in `TdpBackup.config` gespeichert, nicht im Klartext. Entschlüsselt wird es erst unmittelbar vor dem `tdpsqlc.exe`-Aufruf in `TdpBackupHelper.psm1`.
   - **Einschränkung:** `tdpsqlc.exe` selbst nimmt das Passwort nur als Kommandozeilen-Argument entgegen — das ist eine Eigenschaft des TDP-Tools und lässt sich vom PowerShell-Wrapper aus nicht vermeiden. Während der Backup-Ausführung ist das Passwort daher kurzzeitig für lokale Prozess-Inspektion (z.B. `Get-Process`/Task-Manager) sichtbar.
   - `BackupPlan.json` selbst enthält kein Passwort mehr — das TSM-Passwort liegt ausschließlich in `TdpBackup.config`.

2. **Audit-Trail** — Alle Änderungen an `TDP_BackupPlan` werden in `TDP_BackupPlan_Audit` geloggt
   - Wer (ChangedBy)
   - Wann (ChangedDate)
   - Was (OldValues → NewValues)

3. **Fehler-Mails** — Optional: E-Mail-Benachrichtigungen bei Fehlern konfigurieren

---

## 📞 Support & Troubleshooting

```powershell
# Logs anschauen
Get-Content "C:\TDP-Backups\Logs\backup_FULL_*.log" | Select-Object -Last 50

# SQL-Error-Log
SELECT TOP 50 * FROM [master].[dbo].[BackupLog_Errors]
WHERE ErrorDate >= DATEADD(HOUR, -24, GETDATE())
ORDER BY ErrorDate DESC

# PowerShell Debugging
.\Backup-TdpFull.ps1 -Verbose -Debug
```

---

**Version:** 1.0  
**Erstellt:** 2026-07-08  
**Autor:** Claude Code  
**License:** Intern (Bank)
