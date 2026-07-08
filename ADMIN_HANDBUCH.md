# TDP Backup System - Administrationshandbuch

**Version:** 1.0  
**Datum:** 2026-07-08  
**Zielgruppe:** SQL Server & Systemadministratoren  
**Bank-Standard:** ✅ Sicherheit, Audit-Trail, Compliance

---

## 📚 Inhaltsverzeichnis

1. [Schnelleinstieg](#schnelleinstieg)
2. [Tägliche Aufgaben](#tägliche-aufgaben)
3. [Monitoring & Reports](#monitoring--reports)
4. [Troubleshooting](#troubleshooting)
5. [Sicherheit](#sicherheit)
6. [Häufig gestellte Fragen](#häufig-gestellte-fragen)
7. [Support & Kontakt](#support--kontakt)

---

## 🚀 Schnelleinstieg

### Erste 30 Minuten nach Installation

**Schritt 1: Setup-Wizard ausführen**
```powershell
cd "C:\Program Files\Tivoli\TSM\TDPSql\TDP-Backup-System"
.\Setup-TdpBackup.ps1
```

**Was der Wizard fragt:**
- ✓ Welche SQL Server Instance? (z.B. `YOUR-SQL-SERVER`)
- ✓ TSM-Passwort?
- ✓ TDP-Dateien (.opt, .cfg)?
- ✓ Agent-Job erstellen?

**Schritt 2: SQL-Tabellen erstellen**
```powershell
sqlcmd -S YOUR-SQL-SERVER -i "01_TDP_BackupTracking_Setup.sql"
```

**Schritt 3: Datenbanken hinzufügen**
```powershell
.\Configure-BackupPlan.ps1
```
→ GUI öffnet → Tab "Datenbanken" → "+ Datenbank hinzufügen"

**Schritt 4: Testen**
```powershell
.\Backup-TdpFull.ps1
```
→ Sollte erfolgreich durchlaufen (Logs anschauen)

---

## 🗓️ Tägliche Aufgaben

### Was passiert automatisch?

**Täglich um 20:00 Uhr (Agent-Job `TDP_Backup_Daily`):**

```
┌─ SONNTAG (FULL-Backup)
│  └─ Alle Datenbanken (Enabled=true) → FULL sichern
│
├─ MONTAG-SAMSTAG (DIFFERENTIAL-Backup)
│  ├─ DBs mit FULL-Backup → DIFF sichern
│  └─ DBs ohne FULL-Backup → SKIP (warten auf Sonderbehandlung)
│
└─ JEDERZEIT (Sonderbehandlung)
   └─ Neue DBs ohne FULL → sofort FULL durchführen
```

### Status täglich prüfen (3 Minuten)

**SQL Query im SSMS ausführen:**

```sql
-- ✓ Status heute anschauen
EXEC [master].[dbo].[sp_GetBackupStatusReport]
```

**Was du siehst:**
| DB | FullBackupExists | LastFullBackupDate | Fehler? |
|----|------------------|--------------------|---------|
| AdventureWorks | 1 | 2026-07-07 20:15 | ✓ |
| MyAppDB | 1 | 2026-07-07 20:20 | ✓ |
| NewDB | 0 | (null) | ⊘ Warten auf FULL |

**Grünes Häkchen = alles OK** ✓

---

## 📊 Monitoring & Reports

### 1. Täglicher Status (5 Min)

```sql
-- Welche DBs haben aktuelles FULL-Backup?
SELECT TOP 10
    DatabaseName,
    FullBackupExists,
    LastFullBackupDate,
    LastFullBackupStatus
FROM [master].[dbo].[BackupStatus]
ORDER BY LastFullBackupDate DESC
```

### 2. Fehler in letzten 7 Tagen

```sql
-- Was ist schiefgelaufen?
SELECT TOP 50
    DatabaseName,
    BackupType,
    ErrorMessage,
    ExecutionDate
FROM [master].[dbo].[v_FailedBackups]
ORDER BY ExecutionDate DESC
```

### 3. Neue Datenbanken erkennen

```sql
-- DBs ohne FULL-Backup (neu oder fehlgeschlagen)
SELECT *
FROM [master].[dbo].[v_DatabasesWithoutFullBackup]
ORDER BY DaysSinceAdded DESC
```

**Was tun wenn hier was auftaucht?**
- Neue DB? → In Configure-BackupPlan.ps1 hinzufügen
- Zu lange dort? → Logfile prüfen (siehe Troubleshooting)

### 4. Audit-Trail (Compliance)

```sql
-- Wer hat was wann geändert?
EXEC [master].[dbo].[sp_GetAuditTrail] 
    @DatabaseName = NULL,  -- NULL = alle DBs
    @Days = 90
```

**Zeigt:**
- Wer hat DB hinzugefügt/entfernt?
- Wann?
- Von welchem Computer?

---

## 🔧 Troubleshooting

### Problem 1: Agent-Job schlägt fehl

**Symptom:** `TDP_Backup_Daily` Status = FAILED

**Diagnose:**

```powershell
# 1. Job-History anschauen (SSMS)
#    SQL Server Agent → Jobs → TDP_Backup_Daily → View History

# 2. Logfile prüfen
Get-Content "C:\Program Files\Tivoli\TSM\TDPSql\03_Log\Backup_TdpFull_*.log" -Tail 100

# 3. SQL-Fehler checken
sqlcmd -S YOUR-SQL-SERVER -Q "SELECT TOP 20 * FROM [master].[dbo].[BackupLog_Errors]"
```

**Häufige Fehler:**

| Fehler | Ursache | Fix |
|--------|--------|-----|
| "PowerShell not found" | PS-Ausführungsrichtlinie | `Set-ExecutionPolicy RemoteSigned` |
| "SQL connection failed" | SQL offline oder falsche Creds | `sqlcmd -S YOUR-SQL-SERVER -Q "SELECT @@VERSION"` |
| "TDP executable not found" | TDP-Pfad falsch | System-Settings in GUI prüfen |
| "JSON syntax error" | BackupPlan.json kaputt | https://jsonlint.com/ validieren |

### Problem 2: DIFF-Backups fehlgeschlagen

**Symptom:** "Kein FULL-Backup vorhanden"

**Das ist NORMAL!** Neue DBs brauchen erst ein FULL.

**Was passiert:**
1. Neue DB wird erkannt
2. Nächste Nacht: Sonderbehandlung → FULL wird durchgeführt
3. Ab nächsten Tag: DIFF funktioniert

**Lösung:** Warten oder manueller FULL:
```powershell
# Manuell FULL für eine DB starten
$config = Get-Content "C:\Program Files\Tivoli\TSM\TDPSql\BackupPlan.json" | ConvertFrom-Json
$db = "NewDatabaseName"
$tdpDir = "C:\Program Files\Tivoli\TSM\TDPSql"

# Befehl zusammenstellen (wie im Skript)
& "$tdpDir\tdpsqlc.exe" backup $db full /TSMPassword=xxxxx /SQLSERVer=YOUR-SQL-SERVER
```

### Problem 3: Backup dauert zu lange

**Symptom:** Job läuft 3+ Stunden statt 30 Min

**Prüfungen:**

```sql
-- 1. Wieviele DBs gleichzeitig?
SELECT COUNT(*) FROM [master].[dbo].[TDP_BackupPlan] WHERE Enabled=1

-- 2. Größe der DBs?
SELECT name, size*8/1024 AS [SizeMB]
FROM sys.master_files
GROUP BY name, size
ORDER BY size DESC

-- 3. Netzwerk-Traffic OK?
-- → Netzwerk-Admin fragen
```

**Lösungen:**
- Prioritäten setzen (Priority 1-100 in GUI)
- Nachts statt 20:00 → Batch-Wrapper anpassen
- Große DBs aus DIFF ausschließen

### Problem 4: TSM-Passwort vergessen

**Symptom:** Passwort war falsch, Backups schlagen jetzt fehl

**Fix:**

```powershell
# Setup-Wizard nochmal starten (überschreibt Config)
cd "C:\Program Files\Tivoli\TSM\TDPSql\TDP-Backup-System"
.\Setup-TdpBackup.ps1
# → Neues Passwort eingeben
# → Agent-Job wird neu erstellt
```

---

## 🔐 Sicherheit

### Passwort-Management

**Wo ist das TSM-Passwort gespeichert?**
```
C:\Program Files\Tivoli\TSM\TDPSql\TdpBackup.config
                                    ↑
                            Verschlüsselt (PowerShell XML)
                            Nur für Administrator lesbar
```

**Kann es jemand sehen?**
- ✓ Nur Admin (BUILTIN\Administrators)
- ✓ Nicht im JSON
- ✓ Nicht im Source Code
- ✓ Nicht in Logs

**Passwort ändern:**
```powershell
# Alte Config löschen
Remove-Item "C:\Program Files\Tivoli\TSM\TDPSql\TdpBackup.config"

# Setup-Wizard nochmal laufen
.\Setup-TdpBackup.ps1
```

### Audit-Trail & Compliance

**Was wird alles geloggt?**

1. **Welche DBs gesichert?**
   ```sql
   SELECT * FROM [master].[dbo].[BackupLog]
   -- Zeigt: DB, Backup-Typ, Status, Zeit, Fehler
   ```

2. **Wer hat Konfiguration geändert?**
   ```sql
   SELECT * FROM [master].[dbo].[TDP_BackupPlan_Audit]
   -- Zeigt: Wer, Wann, Was vorher/nachher
   ```

3. **Alle Fehler tracken?**
   ```sql
   SELECT * FROM [master].[dbo].[BackupLog_Errors]
   -- Zeigt: Fehler, Severity (ERROR/WARNING/CRITICAL)
   ```

**Aufbewahrung:**
- Logs: 90 Tage (konfigurierbar)
- Audit-Trail: 2+ Jahre (Bank-Standard)

---

## ❓ Häufig gestellte Fragen

### F: Kann ich eine DB vom Backup ausschließen?

**A:** Ja! In der GUI:
1. Configure-BackupPlan.ps1 starten
2. Tab "Datenbanken"
3. DB markieren → "Enabled" = **OFF**
4. Speichern

Nächstes Backup: DB wird übersprungen ✓

---

### F: Neue Datenbank wurde angelegt. Was tun?

**A:** 
1. **Automatisch erkannt?** → Nächste Nacht: Sonderbehandlung (FULL wird durchgeführt)
2. **Schneller haben?** → Manuell hinzufügen:
   ```powershell
   .\Configure-BackupPlan.ps1
   # Tab "Datenbanken" → "+ Datenbank hinzufügen" → "NewDB"
   # Speichern
   # Nächste Nacht: Automatisches FULL
   ```

---

### F: Backup-Fenster ist zu eng. Kann ich zeitlich verschieben?

**A:** Ja! Batch-Wrapper anpassen:

**Datei:** `C:\Program Files\Tivoli\TSM\TDPSql\01_Backup_CMD\Backup_TdpFull.cmd`

```batch
@echo off
REM Zeile ändern: 20:00 → 22:00
REM powershell.exe -NoProfile -ExecutionPolicy Bypass ...
```

Oder in SQL Agent:
1. SSMS → SQL Server Agent → Jobs → TDP_Backup_Daily
2. Schedule → Daily_20_00 → Properties
3. Uhrzeit ändern (z.B. 22:00)

---

### F: Kann ich manuell ein Backup erzwingen?

**A:** Ja!

```powershell
# Vollständiges Backup starten
cd "C:\Program Files\Tivoli\TSM\TDPSql\TDP-Backup-System"
.\Backup-TdpFull.ps1

# Oder über SQL Agent:
# SSMS → SQL Server Agent → Jobs → TDP_Backup_Daily
# → Rechtsklick → "Start Job at Step"
```

---

### F: Wie lange dauert ein Backup?

**A:** 
- Kleine DBs (<1GB): 2-5 Min
- Mittlere DBs (1-10GB): 10-20 Min
- Große DBs (>10GB): 30-60+ Min
- **Gesamt:** Summe aller DBs (FULL am Sonntag dauert länger als DIFF)

**Optimierung:**
- Priority setzen (GUI → Datenbanken Tab)
- Große DBs von DIFF ausschließen
- Netzwerk-Auslastung prüfen

---

### F: Was ist der Unterschied zwischen FULL und DIFF?

**A:**

| FULL | DIFF |
|------|------|
| Komplette DB sichern | Nur Änderungen seit FULL |
| ~100% der Größe | ~10-20% der Größe |
| Sonntag 1x | Mo-Sa täglich |
| Langsam | Schnell |
| Unabhängig | Braucht FULL |

**Beispiel:** DB mit 10GB
- FULL: 10GB (1 Std)
- DIFF: 1-2GB (5 Min)
- Restores schneller wenn mehr DIFFs vorhanden

---

### F: Restore/Wiederherstellung von Backups?

**A:** Das macht TDP direkt (nicht Teil dieses Systems).

```powershell
# TDP-Restore starten (über tdpsqlc.exe)
cd "C:\Program Files\Tivoli\TSM\TDPSql"
.\tdpsqlc.exe restore YourDatabase full /TSMPassword=xxxx /SQLSERVer=YOUR-SQL-SERVER
```

**Dokumentation:** TDP Admin Guide oder TSM-Team

---

### F: Kann ich ein Backup löschen?

**A:** NEIN! TDP/TSM verwaltet die Backups.

```powershell
# Aufbewahrungs-Policy prüfen
# (TSM-Administrator fragen)

# Im SQL-Log aber Einträge löschen? (nach 90 Tagen automatisch)
EXEC [master].[dbo].[sp_CleanupOldLogs] @RetentionDays=90
```

---

### F: Agent-Job wurde deaktiviert. Was tun?

**A:**

```powershell
# Im SSMS prüfen:
# SQL Server Agent → Jobs → TDP_Backup_Daily
# → Status muss "Enabled" sein

# Wenn nicht:
# → Rechtsklick → Properties → "Enabled" = checkmark ✓

# Oder per SQL:
sqlcmd -S YOUR-SQL-SERVER -Q "EXEC msdb.dbo.sp_update_job @job_name='TDP_Backup_Daily', @enabled=1"
```

---

## 📞 Support & Kontakt

### Notfall-Checkliste

**Backups laufen nicht mehr?**

```powershell
# 1. Status prüfen
sqlcmd -S YOUR-SQL-SERVER -Q "SELECT @@VERSION"

# 2. Logs prüfen
Get-ChildItem "C:\Program Files\Tivoli\TSM\TDPSql\03_Log\" | Sort-Object LastWriteTime -Descending | Select-Object -First 5

# 3. Agent-Job Status
sqlcmd -S YOUR-SQL-SERVER -Q "SELECT * FROM msdb.dbo.sysjobs WHERE name='TDP_Backup_Daily'"

# 4. Letzter Error
sqlcmd -S YOUR-SQL-SERVER -Q "SELECT TOP 20 * FROM [master].[dbo].[BackupLog_Errors] ORDER BY [ErrorDate] DESC"

# 5. ALLE Infos sammeln und an Support
```

### Wer ist zuständig?

| Problem | Zuständig | Kontakt |
|---------|-----------|---------|
| PowerShell/GUI nicht da | SQL-Admin | IT-Support |
| SQL Server down | SQL-Admin | IT-Support |
| TSM/TDP Fehler | TSM-Admin | TSM-Team |
| Datenbank Fehler | DB-Owner | Entwicklung |
| Agent-Job stuck | SQL-Admin | IT-Support |

### Dokumentation

- **Installation:** `INSTALLATION.md`
- **Technisch:** `README.md`
- **GitHub:** https://github.com/JankeUwe/TDPBackup

---

## 📋 Checkliste: Erstes Setup

- [ ] Setup-TdpBackup.ps1 ausgeführt
- [ ] SQL-Tabellen erstellt (01_TDP_BackupTracking_Setup.sql)
- [ ] Agent-Job erstellt (02_Create_Agent_Job.sql)
- [ ] Erste Datenbank in GUI hinzugefügt
- [ ] Backup-Skript getestet (manueller Lauf)
- [ ] Logs prüfen (erfolgreich?)
- [ ] Status-Report gelaufen (EXEC sp_GetBackupStatusReport)
- [ ] Team-Schulung durchgeführt
- [ ] Support-Nummer notiert

---

## 📅 Tägliche Checkliste (2 Min)

```
Jeden Morgen um 08:00 Uhr:

□ SQL Query ausführen: EXEC [master].[dbo].[sp_GetBackupStatusReport]
□ Alle DBs "SUCCESS"?
□ Fehler-Spalte leer?
□ Keine offenen Tasks?

Falls NEIN → Troubleshooting Seite konsultieren
Falls JA → ✓ Alles OK, nächster Tag
```

---

## 🎓 Schulung für neues Team

**Dauer:** 2 Stunden

1. **Übersicht** (15 Min)
   - Was macht das System?
   - Warum Sicherheit wichtig?
   - Audit-Trail + Compliance

2. **Hands-On** (60 Min)
   - Gemeinsam Setup-Wizard ausführen
   - GUI bedienen
   - Datenbank hinzufügen
   - Report anschauen

3. **Troubleshooting** (30 Min)
   - Häufige Fehler üben
   - Wer ist zuständig?
   - Escalation Path

4. **Q&A** (15 Min)
   - Fragen beantworten

---

**Letzte Aktualisierung:** 2026-07-08  
**Nächste Review:** 2026-10-08

---

Druckfreundliche Version: Konvertieren zu PDF empfohlen 📄
