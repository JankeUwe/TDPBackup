# GitHub Setup für TDP Backup System

## 📋 Voraussetzungen

1. **Git installiert** — https://git-scm.com/download/win
2. **GitHub Account** — https://github.com
3. **GitHub Desktop (optional)** — https://desktop.github.com

---

## 🚀 Option 1: GitHub-Repo erstellen (empfohlen)

### Step 1: Repo auf GitHub erstellen

1. Gehe zu https://github.com/new
2. Repository name: `CCM-TDP-Backup`
3. Description: `TDP Backup Management System for SQL Server`
4. Public oder Private (für Bank: **PRIVATE**)
5. Klick "Create repository"
6. ✅ Merke dir die URL: `https://github.com/USERNAME/CCM-TDP-Backup.git`

### Step 2: Lokal initialisieren + pushen

```powershell
cd C:\CCM

# Git initialisieren
git init

# GitHub-Remote hinzufügen (deine URL!)
git remote add origin https://github.com/USERNAME/CCM-TDP-Backup.git

# Alle Dateien hinzufügen (außer .gitignore)
git add .

# Ersten Commit erstellen
git commit -m "Initial commit: TDP Backup System mit SQL-Setup, PowerShell-Scripts und GUI"

# Zu GitHub pushen
git branch -M main
git push -u origin main
```

### Step 3: Verifikation

```powershell
# Check Status
git status

# Log anschauen
git log --oneline
```

---

## 🔄 Option 2: Automatisches Setup (Batch-Script)

Speichere folgende Datei als `C:\CCM\setup-github.bat`:

```batch
@echo off
REM ==================================================================
REM GitHub Setup für CCM-TDP-Backup
REM ==================================================================

cd /d C:\CCM

echo.
echo ========================================
echo TDP Backup - GitHub Setup
echo ========================================
echo.

REM Repo-URL eingeben
set /p REPO_URL="Gebe GitHub-Repo-URL ein (https://github.com/USERNAME/CCM-TDP-Backup.git): "

if "%REPO_URL%"=="" (
    echo Fehler: Repo-URL erforderlich
    exit /b 1
)

REM Git initialisieren
echo.
echo [1/5] Git initialisieren...
git init
if %ERRORLEVEL% NEQ 0 (
    echo Fehler: Git nicht installiert? https://git-scm.com/download/win
    exit /b 1
)

REM Remote hinzufügen
echo.
echo [2/5] GitHub-Remote hinzufügen...
git remote add origin %REPO_URL%

REM Dateien hinzufügen
echo.
echo [3/5] Dateien zu Git hinzufügen...
git add .

REM Commit erstellen
echo.
echo [4/5] Ersten Commit erstellen...
git commit -m "Initial commit: TDP Backup System mit SQL-Setup, PowerShell-Scripts und GUI"
if %ERRORLEVEL% NEQ 0 (
    echo Fehler beim Commit. Git konfigurieren:
    echo git config user.email "admin@yourbank.de"
    echo git config user.name "Admin"
    exit /b 1
)

REM Zu GitHub pushen
echo.
echo [5/5] Zu GitHub pushen...
git branch -M main
git push -u origin main

if %ERRORLEVEL% NEQ 0 (
    echo Fehler beim Push. Prüfe:
    echo - Repo-URL ist korrekt?
    echo - Hast du SSH-Key oder Token konfiguriert?
    exit /b 1
)

echo.
echo ========================================
echo ✓ GitHub Setup erfolgreich!
echo ========================================
echo.
echo Repo: %REPO_URL%
echo Branch: main
echo.
echo Nächste Schritte:
echo 1. https://github.com prüfen - Dateien sollten sichtbar sein
echo 2. Kunden können mit "git clone <URL>" downloaden
echo.
pause
```

Ausführen:
```powershell
C:\CCM\setup-github.bat
```

---

## 📥 Für Kunden: Installation aus GitHub

```powershell
# TDP-Backup-System klonen
git clone https://github.com/USERNAME/CCM-TDP-Backup.git C:\TDP-Backups-Setup

cd C:\TDP-Backups-Setup

# SQL-Setup ausführen
sqlcmd -S YOUR-SQL-SERVER -i "01_TDP_BackupTracking_Setup.sql"

# JSON-Konfiguration editieren mit GUI
.\Configure-BackupPlan.ps1

# Backup-Skript testen
.\Backup-TdpFull.ps1 -SqlServer YOUR-SQL-SERVER
```

---

## 🔐 SSH-Key Setup (für sichere Verbindung)

```powershell
# SSH-Key generieren
ssh-keygen -t ed25519 -C "admin@yourbank.de"

# Key anzeigen
Get-Content ~/.ssh/id_ed25519.pub

# Kopiere den Key zu GitHub: Settings → SSH Keys → New
```

Dann mit SSH pushen:
```powershell
git remote set-url origin git@github.com:USERNAME/CCM-TDP-Backup.git
git push
```

---

## 📦 Updates verteilen

Nach Änderungen:
```powershell
cd C:\CCM

# Änderungen hinzufügen
git add SQL-Tools/TDP-Backup/

# Commit
git commit -m "Update: Fehlerfix in TdpBackupHelper.psm1"

# Push
git push
```

Kunden können mit `git pull` aktualisieren:
```powershell
cd C:\TDP-Backups-Setup
git pull  # = neueste Version herunterladen
```

---

## ✅ Checklist

- [ ] GitHub-Repo erstellt
- [ ] Git lokal initialisiert
- [ ] Dateien zu Git hinzugefügt
- [ ] Ersten Commit gepusht
- [ ] GitHub-URL in Dokumentation dokumentiert
- [ ] Team-Zugriff konfiguriert (falls nötig)
- [ ] SSH-Key eingerichtet (optional)

---

## 🆘 Häufige Fehler

| Fehler | Lösung |
|--------|--------|
| "Git: command not found" | Git installieren: https://git-scm.com/download/win |
| "fatal: not a git repository" | `git init` im Verzeichnis ausführen |
| "Please tell me who you are" | `git config user.email "admin@yourbank.de"` und `git config user.name "Admin"` |
| "Permission denied (publickey)" | SSH-Key nicht konfiguriert (siehe SSH-Key Setup oben) |
| "Error: fatal: could not read Username" | Token statt Passwort verwenden (Settings → Developer settings → Personal access tokens) |

---

**Fragen?** Schau die GitHub Docs: https://docs.github.com
