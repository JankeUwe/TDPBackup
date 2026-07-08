# ==============================================================================
# Setup-TdpBackup.ps1 - Einmalige Konfiguration für TDP Backup System
# ==============================================================================
# Dieser Wizard führt die Bank durch die einmalige Konfiguration:
# - SQL Server Instance
# - TSM-Passwort
# - TDP-Parameter
# - Agent-Job erstellen
#
# USAGE:
#   .\Setup-TdpBackup.ps1 -SQLInstance "YOUR-SQL-SERVER" -TSMPassword "xxx" -SQLSERVer "YOUR-SQL-SERVER"
#   .\Setup-TdpBackup.ps1  (interaktiv)
# ==============================================================================

param(
    [string]$SQLInstance = "",
    [string]$TSMPassword = "",
    [string]$SQLSERVer = ""
)

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

# ==============================================================================
# KONFIGURATIONSDATEI
# ==============================================================================

$TdpDir = "C:\Program Files\Tivoli\TSM\TDPSql"
$ConfigDir = $TdpDir
$ConfigFile = "$ConfigDir\TdpBackup.config"

function Save-Config {
    param(
        [string]$SQLInstance,
        [string]$TSMPassword,
        [string]$SQLServer,
        [string]$TsmOptFile,
        [string]$TdpConfigFile
    )

    $config = @{
        SQLInstance = $SQLInstance
        TSMPassword = $TSMPassword
        SQLServer = $SQLServer
        TsmOptFile = $TsmOptFile
        TdpConfigFile = $TdpConfigFile
        SetupDate = Get-Date
    }

    $config | Export-Clixml -Path $ConfigFile -Force
    Write-Host "✓ Konfiguration gespeichert: $ConfigFile"
}

function Load-Config {
    if (Test-Path $ConfigFile) {
        $config = Import-Clixml -Path $ConfigFile
        return $config
    }
    return $null
}

function Test-SqlConnection {
    param([string]$Instance)

    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection
        $conn.ConnectionString = "Server=$Instance;Database=master;Integrated Security=true;Connection Timeout=5"
        $conn.Open()
        $conn.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Test-TdpConnection {
    param([string]$TdpDir)

    $tdpsqlc = "$TdpDir\tdpsqlc.exe"
    if (Test-Path $tdpsqlc) {
        return $true
    }
    return $false
}

# ==============================================================================
# SETUP-FORM (GUI)
# ==============================================================================

function Show-ScenarioSelection {
    $formScenario = New-Object System.Windows.Forms.Form
    $formScenario.Text = "TDP Backup System - Szenario-Auswahl"
    $formScenario.Size = New-Object System.Drawing.Size(700, 500)
    $formScenario.StartPosition = "CenterScreen"
    $formScenario.BackColor = [System.Drawing.Color]::White

    # TITLE
    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Wähle eine Backup-Strategie"
    $title.Font = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
    $title.Location = New-Object System.Drawing.Point(20, 20)
    $title.Size = New-Object System.Drawing.Size(650, 30)
    $formScenario.Controls.Add($title)

    # SCENARIOS
    $scenarios = @(
        @{
            Name = "Szenario 1: Standard-Bank (EMPFOHLEN)"
            Description = "FULL: Sonntag`nDIFF: Montag-Samstag`nSpeicher: Optimal"
            FullDays = @("Sunday")
            DiffDays = @("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
        },
        @{
            Name = "Szenario 2: Maximale Verfügbarkeit"
            Description = "FULL: Jeden Tag`nDIFF: Keine`nSpeicher: Maximum"
            FullDays = @("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
            DiffDays = @()
        },
        @{
            Name = "Szenario 3: Schnelle Recovery"
            Description = "FULL: Mittwoch + Sonntag`nDIFF: Mo, Di, Do, Fr, Sa`nSpeicher: Mittel"
            FullDays = @("Sunday", "Wednesday")
            DiffDays = @("Monday", "Tuesday", "Thursday", "Friday", "Saturday")
        },
        @{
            Name = "Szenario 4: Individuell"
            Description = "Benutzerdefinierte Konfiguration`nWähle selbst FULL/DIFF Tage"
            FullDays = @()
            DiffDays = @()
            IsCustom = $true
        }
    )

    $selectedScenario = $null
    $y = 70

    foreach ($scenario in $scenarios) {
        $radio = New-Object System.Windows.Forms.RadioButton
        $radio.Text = $scenario.Name
        $radio.Location = New-Object System.Drawing.Point(20, $y)
        $radio.Size = New-Object System.Drawing.Size(650, 20)
        $radio.Tag = $scenario
        $formScenario.Controls.Add($radio)
        $y += 25

        $desc = New-Object System.Windows.Forms.Label
        $desc.Text = "  " + ($scenario.Description -replace "`n", "`n  ")
        $desc.Location = New-Object System.Drawing.Point(40, $y)
        $desc.Size = New-Object System.Drawing.Size(620, 50)
        $desc.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Italic)
        $formScenario.Controls.Add($desc)
        $y += 60

        # Standard-Szenario selektieren
        if ($scenario.Name -match "Standard-Bank") {
            $radio.Checked = $true
            $selectedScenario = $scenario
        }
    }

    $btnNext = New-Object System.Windows.Forms.Button
    $btnNext.Text = "Weiter >"
    $btnNext.Location = New-Object System.Drawing.Point(550, 430)
    $btnNext.Size = New-Object System.Drawing.Size(120, 30)
    $btnNext.BackColor = [System.Drawing.Color]::LightGreen
    $btnNext.Add_Click({
        foreach ($control in $formScenario.Controls) {
            if ($control -is [System.Windows.Forms.RadioButton] -and $control.Checked) {
                $selectedScenario = $control.Tag
                break
            }
        }
        $formScenario.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $formScenario.Close()
    })
    $formScenario.Controls.Add($btnNext)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Abbrechen"
    $btnCancel.Location = New-Object System.Drawing.Point(460, 430)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 30)
    $btnCancel.Add_Click({
        $formScenario.Close()
    })
    $formScenario.Controls.Add($btnCancel)

    $result = $formScenario.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $selectedScenario
    }
    return $null
}

function Show-SetupWizard {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "TDP Backup System - Setup Wizard"
    $form.Size = New-Object System.Drawing.Size(600, 500)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.Color]::White

    # TITLE
    $title = New-Object System.Windows.Forms.Label
    $title.Text = "TDP Backup System - Systemkonfiguration"
    $title.Font = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
    $title.Location = New-Object System.Drawing.Point(20, 20)
    $title.Size = New-Object System.Drawing.Size(550, 30)
    $form.Controls.Add($title)

    # SQL INSTANCE
    $label1 = New-Object System.Windows.Forms.Label
    $label1.Text = "SQL Server Instance:"
    $label1.Location = New-Object System.Drawing.Point(20, 70)
    $label1.Size = New-Object System.Drawing.Size(150, 20)
    $form.Controls.Add($label1)

    $textSqlInstance = New-Object System.Windows.Forms.TextBox
    $textSqlInstance.Text = $SQLInstance -eq "" ? "YOUR-SQL-SERVER" : $SQLInstance
    $textSqlInstance.Location = New-Object System.Drawing.Point(180, 70)
    $textSqlInstance.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($textSqlInstance)

    $btnTestSql = New-Object System.Windows.Forms.Button
    $btnTestSql.Text = "Test"
    $btnTestSql.Location = New-Object System.Drawing.Point(490, 70)
    $btnTestSql.Size = New-Object System.Drawing.Size(60, 20)
    $btnTestSql.Add_Click({
        if (Test-SqlConnection -Instance $textSqlInstance.Text) {
            [System.Windows.Forms.MessageBox]::Show("✓ Verbindung OK!", "SQL Server",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information)
        } else {
            [System.Windows.Forms.MessageBox]::Show("✗ Verbindung fehlgeschlagen!", "SQL Server",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $form.Controls.Add($btnTestSql)

    # TSM PASSWORT
    $label2 = New-Object System.Windows.Forms.Label
    $label2.Text = "TSM-Passwort:"
    $label2.Location = New-Object System.Drawing.Point(20, 110)
    $label2.Size = New-Object System.Drawing.Size(150, 20)
    $form.Controls.Add($label2)

    $textPassword = New-Object System.Windows.Forms.TextBox
    $textPassword.Text = $TSMPassword
    $textPassword.PasswordChar = '*'
    $textPassword.Location = New-Object System.Drawing.Point(180, 110)
    $textPassword.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($textPassword)

    # TDP OPT FILE
    $label3 = New-Object System.Windows.Forms.Label
    $label3.Text = "TSM Opt-File:"
    $label3.Location = New-Object System.Drawing.Point(20, 150)
    $label3.Size = New-Object System.Drawing.Size(150, 20)
    $form.Controls.Add($label3)

    $textTsmOptFile = New-Object System.Windows.Forms.TextBox
    $textTsmOptFile.Text = "$TdpDir\dsm.opt"
    $textTsmOptFile.Location = New-Object System.Drawing.Point(180, 150)
    $textTsmOptFile.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($textTsmOptFile)

    $btnBrowseOpt = New-Object System.Windows.Forms.Button
    $btnBrowseOpt.Text = "..."
    $btnBrowseOpt.Location = New-Object System.Drawing.Point(490, 150)
    $btnBrowseOpt.Size = New-Object System.Drawing.Size(60, 20)
    $btnBrowseOpt.Add_Click({
        $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openFileDialog.Filter = "Opt Files|*.opt|All Files|*.*"
        $openFileDialog.InitialDirectory = $TdpDir
        if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $textTsmOptFile.Text = $openFileDialog.FileName
        }
    })
    $form.Controls.Add($btnBrowseOpt)

    # TDP CONFIG FILE
    $label4 = New-Object System.Windows.Forms.Label
    $label4.Text = "TDP Config-File:"
    $label4.Location = New-Object System.Drawing.Point(20, 190)
    $label4.Size = New-Object System.Drawing.Size(150, 20)
    $form.Controls.Add($label4)

    $textTdpConfigFile = New-Object System.Windows.Forms.TextBox
    $textTdpConfigFile.Text = "$TdpDir\tdpsql.cfg"
    $textTdpConfigFile.Location = New-Object System.Drawing.Point(180, 190)
    $textTdpConfigFile.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($textTdpConfigFile)

    $btnBrowseCfg = New-Object System.Windows.Forms.Button
    $btnBrowseCfg.Text = "..."
    $btnBrowseCfg.Location = New-Object System.Drawing.Point(490, 190)
    $btnBrowseCfg.Size = New-Object System.Drawing.Size(60, 20)
    $btnBrowseCfg.Add_Click({
        $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openFileDialog.Filter = "Config Files|*.cfg|All Files|*.*"
        $openFileDialog.InitialDirectory = $TdpDir
        if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $textTdpConfigFile.Text = $openFileDialog.FileName
        }
    })
    $form.Controls.Add($btnBrowseCfg)

    # INFO TEXT
    $infoText = New-Object System.Windows.Forms.Label
    $infoText.Text = "Diese Einstellungen werden für alle Backups verwendet.`nSie können später in Configure-BackupPlan.ps1 geändert werden."
    $infoText.Location = New-Object System.Drawing.Point(20, 240)
    $infoText.Size = New-Object System.Drawing.Size(550, 50)
    $infoText.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Italic)
    $form.Controls.Add($infoText)

    # BUTTONS
    $btnSetup = New-Object System.Windows.Forms.Button
    $btnSetup.Text = "Setup & Agent-Job erstellen"
    $btnSetup.Location = New-Object System.Drawing.Point(300, 420)
    $btnSetup.Size = New-Object System.Drawing.Size(150, 30)
    $btnSetup.BackColor = [System.Drawing.Color]::LightGreen
    $btnSetup.Add_Click({
        # Validierung
        if ([string]::IsNullOrWhiteSpace($textSqlInstance.Text)) {
            [System.Windows.Forms.MessageBox]::Show("SQL Instance erforderlich!", "Fehler",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        if ([string]::IsNullOrWhiteSpace($textPassword.Text)) {
            [System.Windows.Forms.MessageBox]::Show("TSM-Passwort erforderlich!", "Fehler",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        # Config speichern
        Save-Config `
            -SQLInstance $textSqlInstance.Text `
            -TSMPassword $textPassword.Text `
            -SQLServer $textSqlInstance.Text `
            -TsmOptFile $textTsmOptFile.Text `
            -TdpConfigFile $textTdpConfigFile.Text

        # Agent-Job erstellen
        Create-AgentJob -SQLInstance $textSqlInstance.Text

        $form.Close()
    })
    $form.Controls.Add($btnSetup)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Abbrechen"
    $btnCancel.Location = New-Object System.Drawing.Point(460, 420)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 30)
    $btnCancel.Add_Click({
        $form.Close()
    })
    $form.Controls.Add($btnCancel)

    $form.ShowDialog() | Out-Null
}

function Create-AgentJob {
    param([string]$SQLInstance)

    Write-Host ""
    Write-Host "========== SQL Agent Job wird erstellt =========="
    Write-Host "Instance: $SQLInstance"
    Write-Host ""

    # SQL-Script ausführen
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $setupSqlFile = "$scriptPath\02_Create_Agent_Job.sql"

    if (Test-Path $setupSqlFile) {
        try {
            sqlcmd -S $SQLInstance -i $setupSqlFile
            Write-Host ""
            Write-Host "✓ Agent-Job erfolgreich erstellt!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Job läuft täglich um 20:00 Uhr"
            Write-Host "Logs: C:\Program Files\Tivoli\TSM\TDPSql\03_Log\"
        }
        catch {
            Write-Error "Fehler beim Erstellen des Agent-Jobs: $_"
        }
    }
    else {
        Write-Error "Setup-SQL-Datei nicht gefunden: $setupSqlFile"
    }
}

# ==============================================================================
# MAIN
# ==============================================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TDP Backup System - Setup Wizard" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Prüfe ob Konfiguration bereits existiert
$existingConfig = Load-Config
if ($null -ne $existingConfig) {
    Write-Host "Bestehende Konfiguration gefunden:"
    Write-Host "  Instance: $($existingConfig.SQLInstance)"
    Write-Host ""

    $overwrite = Read-Host "Möchtest du die Konfiguration überschreiben? (J/N)"
    if ($overwrite -ne "J") {
        Write-Host "Setup abgebrochen."
        exit 0
    }
}

# Show GUI
Show-SetupWizard

Write-Host ""
Write-Host "✓ Setup abgeschlossen!" -ForegroundColor Green
Write-Host ""
Write-Host "Nächste Schritte:"
Write-Host "  1. SQL Setup ausführen:"
Write-Host "     sqlcmd -S <Instance> -i 01_TDP_BackupTracking_Setup.sql"
Write-Host ""
Write-Host "  2. Datenbanken konfigurieren:"
Write-Host "     .\Configure-BackupPlan.ps1"
Write-Host ""
Write-Host "  3. Backup-Skript testen:"
Write-Host "     .\Backup-TdpFull.ps1"
Write-Host ""
