# TDP Backup System - Architektur & Design

**Version:** 1.0  
**Konzept:** 1 intelligenter Job statt 2 separate Jobs  
**Zielgruppe:** Administratoren, Developer, Architekten

---

## 🎯 Kernidee: 1 Job für alle Szenarien

### **Vorher (2 separate Jobs - alt):**

```
┌──────────────────────────┐          ┌──────────────────────────┐
│   backup_all_full.cmd    │          │   backup_all_diff.cmd    │
├──────────────────────────┤          ├──────────────────────────┤
│ Sonntag 20:00 Uhr        │          │ Mo-Sa 20:00 Uhr          │
│ FULL alle Datenbanken    │          │ DIFF alle Datenbanken    │
│                          │          │                          │
│ Hardcoded:               │          │ Hardcoded:               │
│ backup * full            │          │ backup * diff            │
└──────────────────────────┘          └──────────────────────────┘
        ↓                                     ↓
        Problem: Kundenspezifisch?
        → Neuer Job nötig
        → Doppelte Logik
        → Schwer zu warten
```

### **Nachher (1 intelligenter Job - neu):**

```
┌──────────────────────────────────────────────────┐
│     TDP_Backup_Daily (täglich 20:00 Uhr)        │
├──────────────────────────────────────────────────┤
│                                                  │
│  Liest BackupPlan.json:                         │
│  ├─ FullBackupDays: ["Sunday"]                 │
│  └─ DifferentialBackupDays: ["Mo"..."Sa"]      │
│                                                  │
│  Entscheidungslogik:                            │
│  ├─ Ist heute FULL-Tag?                        │
│  │  └─ Ja: FULL durchführen                   │
│  ├─ Ist heute DIFF-Tag?                        │
│  │  └─ Ja: DIFF durchführen                   │
│  └─ DBs ohne FULL?                             │
│     └─ Ja: Sonderbehandlung (sofort FULL)     │
│                                                  │
│  Alles geloggt & getracked in SQL              │
└──────────────────────────────────────────────────┘
        ↓
        ✓ Flexibel für alle Szenarien
        ✓ Zentrale Logik (wartbar)
        ✓ Konfigurierbar (JSON)
        ✓ 1 Job für alle Kunden
```

---

## 📊 Vergleich: Alte vs. Neue Architektur

| Aspekt | **VORHER (2 Jobs)** | **NACHHER (1 Job)** |
|--------|---------------------|---------------------|
| **Anzahl Jobs** | 2 (backup_full + backup_diff) | 1 (TDP_Backup_Daily) |
| **Zeitplan** | Hard 2x fixed | Dynamisch aus JSON |
| **FULL-Tage** | Nur Sonntag (hardcoded) | Beliebig konfigurierbar |
| **DIFF-Tage** | Nur Mo-Sa (hardcoded) | Beliebig konfigurierbar |
| **Kundenspezifisch** | Nicht möglich (neuer Job) | JSON anpassen |
| **Logik-Duplikate** | Ja (beide Jobs ähnlich) | Nein (zentral) |
| **Fehlerbehandlung** | 2x implementiert | 1x zentral |
| **Logs** | 2 getrennte Logs | 1 zentrales Log |
| **Wartung** | Komplex | Einfach |
| **Skalierung** | Schlecht (n Jobs für n Szenarien) | Gut (1 Job für alle) |

---

## 🔄 Workflow: Wie der 1 Job funktioniert

### **Jeden Tag um 20:00 Uhr:**

```python
def TDP_Backup_Daily():
    # 1. Konfiguration laden
    config = load_json("BackupPlan.json")
    schedule = config["Schedule"]
    
    today = get_day_of_week()  # "Monday", "Sunday", etc.
    
    # 2. SONDERBEHANDLUNG: DBs ohne FULL
    if config["AllowSpecialHandling"]:
        dbs_without_full = query_sql("SELECT * FROM BackupStatus WHERE FullBackupExists=0")
        for db in dbs_without_full:
            execute_tdp_backup(db, "FULL")  # Sofort FULL, egal welcher Tag!
    
    # 3. Reguläre FULL-Backups
    if today in schedule["FullBackupDays"]:
        all_dbs = query_sql("SELECT * FROM TDP_BackupPlan WHERE Enabled=1")
        for db in all_dbs:
            execute_tdp_backup(db, "FULL")
    
    # 4. Reguläre DIFF-Backups
    if today in schedule["DifferentialBackupDays"]:
        diff_dbs = query_sql("""
            SELECT * FROM TDP_BackupPlan 
            WHERE Enabled=1 AND IncludeInDifferential=1
        """)
        for db in diff_dbs:
            if has_full_backup(db):  # Nur wenn FULL existiert!
                execute_tdp_backup(db, "DIFF")
            else:
                log_skipped(db, "No FULL backup yet")
    
    # 5. Alles in SQL-Tabellen loggen
    update_backup_log()
    update_audit_trail()
```

---

## 🎛️ Konfigurierbare Szenarien

Der **1 Job kann alle Szenarien** durch JSON-Änderung realisieren:

### **Szenario 1: Standard-Bank**
```json
{
  "Scenario": "Szenario 1: Standard-Bank",
  "Schedule": {
    "FullBackupDays": ["Sunday"],
    "DifferentialBackupDays": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],
    "AllowSpecialHandling": true
  }
}
```
→ **1 Job (20:00)**: Sonntag FULL, Mo-Sa DIFF

---

### **Szenario 2: Maximale Verfügbarkeit**
```json
{
  "Scenario": "Szenario 2: Maximale Verfügbarkeit",
  "Schedule": {
    "FullBackupDays": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
    "DifferentialBackupDays": [],
    "AllowSpecialHandling": false
  }
}
```
→ **1 Job (20:00)**: Jeden Tag FULL, keine DIFF

---

### **Szenario 3: Schnelle Recovery**
```json
{
  "Scenario": "Szenario 3: Schnelle Recovery",
  "Schedule": {
    "FullBackupDays": ["Sunday", "Wednesday"],
    "DifferentialBackupDays": ["Monday", "Tuesday", "Thursday", "Friday", "Saturday"],
    "AllowSpecialHandling": true
  }
}
```
→ **1 Job (20:00)**: So+Mi FULL, Mo-Di-Do-Fr-Sa DIFF

---

### **Szenario 4: Custom (Kunde möchte zeitversetzt)**
```json
{
  "Scenario": "Szenario 4: Custom mit 2 Jobs",
  "Jobs": [
    {
      "Name": "TDP_Backup_FULL",
      "Time": "19:00",
      "Schedule": {
        "FullBackupDays": ["Sunday", "Wednesday"],
        "DifferentialBackupDays": []
      }
    },
    {
      "Name": "TDP_Backup_DIFF", 
      "Time": "21:00",
      "Schedule": {
        "FullBackupDays": [],
        "DifferentialBackupDays": ["Monday", "Tuesday", "Thursday", "Friday", "Saturday"]
      }
    }
  ]
}
```
→ **2 Jobs (optional)**: FULL 19:00, DIFF 21:00 (zeitversetzt)

---

## 💾 Datenflusss

```
BackupPlan.json
    ↓
Setup-TdpBackup.ps1 (Szenario auswählen)
    ↓
[master].[dbo].[TDP_BackupPlan] (Config Spiegelbild)
    ↓
Backup-TdpFull.ps1 (täglich 20:00 Uhr)
    ├─ Liest Schedule aus JSON
    ├─ Entscheidet: FULL oder DIFF?
    ├─ Führt TDP-Backup durch
    └─ Loggt in SQL-Tabellen:
        ├─ [BackupStatus] (Status pro DB)
        ├─ [BackupLog] (Alle Runs)
        ├─ [BackupLog_Errors] (Fehler)
        └─ [TDP_BackupPlan_Audit] (Änderungen)
```

---

## 🚀 Skalierung: Mehrere SQL Server?

Jede Instanz hat ihren eigenen Job, aber **gleichen Code**:

```
SRPSDSQL011:
  └─ Job: TDP_Backup_Daily
     └─ Backup-TdpFull.ps1 (mit SRPSDSQL011-Config)

SRPSDSQL012:
  └─ Job: TDP_Backup_Daily
     └─ Backup-TdpFull.ps1 (mit SRPSDSQL012-Config)

SRPSDSQL013:
  └─ Job: TDP_Backup_Daily
     └─ Backup-TdpFull.ps1 (mit SRPSDSQL013-Config)

→ Alle 3 Instanzen: GLEICHER Code, UNTERSCHIEDLICHE Config
→ 1 Maintenance = 3x Instanzen gefixt ✓
```

---

## 🎓 Vorteile für eure Kunden

| Vorteil | Nutzen |
|---------|--------|
| **1 Job** | Einfacher zu verwalten, weniger Fehler |
| **Flexibel** | Konfigurierbar ohne Code-Änderung |
| **Transparent** | Alles in JSON sichtbar |
| **Skalierbar** | 1 Code für 100 Kunden |
| **Wartbar** | Zentrale Logik, einfach zu updaten |
| **Robust** | Sonderbehandlung für neue DBs |

---

## 📝 Implementierungs-Checkliste

- [x] Backup-TdpFull.ps1 liest Schedule aus JSON
- [x] Setup-Wizard bietet Szenarien
- [x] 1 Agent-Job wird erstellt
- [x] Sonderbehandlung für neue DBs
- [x] SQL-Logging für alle Runs
- [x] Audit-Trail für Compliance

---

**Result: Ein produktionsreifes System für flexible Backup-Strategien!** 🎉
