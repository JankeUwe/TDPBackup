# ==============================================================================
# Configure-BackupPlan.ps1 - GUI für JSON-Konfiguration
# Windows Forms basiert (wie sqmSqlTool)
# Kunde kann Datenbanken hinzufügen/entfernen OHNE die JSON zu editieren
# ==============================================================================

param(
    [string]$ConfigPath = "C:\TDP-Backups\Config\BackupPlan.json"
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# ==============================================================================
# Konfiguration laden
# ==============================================================================

function Load-Config {
    if (-not (Test-Path $ConfigPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Konfigurationsdatei nicht gefunden: $ConfigPath",
            "Fehler",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }

    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        return $config
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Fehler beim Laden der JSON-Datei: $_",
            "JSON-Fehler",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }
}

function Save-Config {
    param([object]$Config)

    try {
        $json = $Config | ConvertTo-Json -Depth 10 -Encoding UTF8
        Set-Content -Path $ConfigPath -Value $json -Encoding UTF8

        [System.Windows.Forms.MessageBox]::Show(
            "Konfiguration gespeichert!",
            "Erfolgreich",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return $true
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Fehler beim Speichern: $_",
            "Fehler",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $false
    }
}

# ==============================================================================
# Haupt-Form
# ==============================================================================

$form = New-Object System.Windows.Forms.Form
$form.Text = "TDP Backup Plan - Konfiguration"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::White

$config = Load-Config

# ==============================================================================
# TAB CONTROL
# ==============================================================================

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabControl.Padding = New-Object System.Drawing.Point(10, 10)

# TAB 1: DATENBANKEN
$tabDatabases = New-Object System.Windows.Forms.TabPage
$tabDatabases.Text = "Datenbanken"
$tabDatabases.BackColor = [System.Drawing.Color]::White

# TAB 2: EINSTELLUNGEN
$tabSettings = New-Object System.Windows.Forms.TabPage
$tabSettings.Text = "Einstellungen"
$tabSettings.BackColor = [System.Drawing.Color]::White

# TAB 3: SYSTEM-SETTINGS
$tabSystemSettings = New-Object System.Windows.Forms.TabPage
$tabSystemSettings.Text = "System-Settings"
$tabSystemSettings.BackColor = [System.Drawing.Color]::White

# TAB 4: INFO
$tabInfo = New-Object System.Windows.Forms.TabPage
$tabInfo.Text = "Info"
$tabInfo.BackColor = [System.Drawing.Color]::White

$tabControl.TabPages.Add($tabDatabases)
$tabControl.TabPages.Add($tabSettings)
$tabControl.TabPages.Add($tabSystemSettings)
$tabControl.TabPages.Add($tabInfo)

# ==============================================================================
# TAB 1: DATENBANKEN
# ==============================================================================

$labelDatabases = New-Object System.Windows.Forms.Label
$labelDatabases.Text = "Gesicherte Datenbanken:"
$labelDatabases.Location = New-Object System.Drawing.Point(10, 10)
$labelDatabases.Size = New-Object System.Drawing.Size(200, 20)

$dataGridDatabases = New-Object System.Windows.Forms.DataGridView
$dataGridDatabases.Location = New-Object System.Drawing.Point(10, 35)
$dataGridDatabases.Size = New-Object System.Drawing.Size(750, 350)
$dataGridDatabases.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$dataGridDatabases.AllowUserToAddRows = $false
$dataGridDatabases.AllowUserToDeleteRows = $false
$dataGridDatabases.ReadOnly = $true
$dataGridDatabases.BackgroundColor = [System.Drawing.Color]::White

# Spalten hinzufügen
$dataGridDatabases.Columns.Add((New-Object System.Windows.Forms.DataGridViewTextBoxColumn -Property @{
    Name = "DatabaseName"
    HeaderText = "Datenbank"
    Width = 150
}))

$enabledColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$enabledColumn.Name = "Enabled"
$enabledColumn.HeaderText = "Aktiviert"
$enabledColumn.Width = 80
$enabledColumn.ReadOnly = $false
$dataGridDatabases.Columns.Add($enabledColumn)

$diffColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$diffColumn.Name = "IncludeInDifferential"
$diffColumn.HeaderText = "DIFF"
$diffColumn.Width = 60
$diffColumn.ReadOnly = $false
$dataGridDatabases.Columns.Add($diffColumn)

$dataGridDatabases.Columns.Add((New-Object System.Windows.Forms.DataGridViewTextBoxColumn -Property @{
    Name = "Priority"
    HeaderText = "Priorität (1-100)"
    Width = 100
}))

$dataGridDatabases.Columns.Add((New-Object System.Windows.Forms.DataGridViewTextBoxColumn -Property @{
    Name = "Notes"
    HeaderText = "Notizen"
    Width = 200
}))

# Daten laden
foreach ($db in $config.SelectedDatabases) {
    $row = New-Object System.Windows.Forms.DataGridViewRow
    $row.Cells.Add((New-Object System.Windows.Forms.DataGridViewTextBoxCell -Property @{ Value = $db.Name }))
    $row.Cells.Add((New-Object System.Windows.Forms.DataGridViewCheckBoxCell -Property @{ Value = $db.Enabled }))
    $row.Cells.Add((New-Object System.Windows.Forms.DataGridViewCheckBoxCell -Property @{ Value = $db.IncludeInDifferential }))
    $row.Cells.Add((New-Object System.Windows.Forms.DataGridViewTextBoxCell -Property @{ Value = $db.Priority }))
    $row.Cells.Add((New-Object System.Windows.Forms.DataGridViewTextBoxCell -Property @{ Value = $db.Notes }))
    $dataGridDatabases.Rows.Add($row)
}

$tabDatabases.Controls.Add($labelDatabases)
$tabDatabases.Controls.Add($dataGridDatabases)

# Buttons unter Tabelle
$buttonAddDatabase = New-Object System.Windows.Forms.Button
$buttonAddDatabase.Text = "+ Datenbank hinzufügen"
$buttonAddDatabase.Location = New-Object System.Drawing.Point(10, 390)
$buttonAddDatabase.Size = New-Object System.Drawing.Size(150, 30)
$buttonAddDatabase.BackColor = [System.Drawing.Color]::LightGreen

$buttonRemoveDatabase = New-Object System.Windows.Forms.Button
$buttonRemoveDatabase.Text = "- Ausgewählte entfernen"
$buttonRemoveDatabase.Location = New-Object System.Drawing.Point(170, 390)
$buttonRemoveDatabase.Size = New-Object System.Drawing.Size(150, 30)
$buttonRemoveDatabase.BackColor = [System.Drawing.Color]::LightCoral

$buttonAddDatabase.Add_Click({
    $form2 = New-Object System.Windows.Forms.Form
    $form2.Text = "Neue Datenbank"
    $form2.Size = New-Object System.Drawing.Size(400, 250)
    $form2.StartPosition = "CenterParent"

    $label1 = New-Object System.Windows.Forms.Label
    $label1.Text = "Datenbankname:"
    $label1.Location = New-Object System.Drawing.Point(10, 10)
    $label1.Size = New-Object System.Drawing.Size(100, 20)

    $textName = New-Object System.Windows.Forms.TextBox
    $textName.Location = New-Object System.Drawing.Point(120, 10)
    $textName.Size = New-Object System.Drawing.Size(260, 20)

    $checkEnabled = New-Object System.Windows.Forms.CheckBox
    $checkEnabled.Text = "Aktiviert"
    $checkEnabled.Location = New-Object System.Drawing.Point(10, 40)
    $checkEnabled.Checked = $true

    $checkDiff = New-Object System.Windows.Forms.CheckBox
    $checkDiff.Text = "In Differential-Backups einschließen"
    $checkDiff.Location = New-Object System.Drawing.Point(10, 65)
    $checkDiff.Checked = $true

    $label2 = New-Object System.Windows.Forms.Label
    $label2.Text = "Priorität (1-100):"
    $label2.Location = New-Object System.Drawing.Point(10, 90)
    $label2.Size = New-Object System.Drawing.Size(100, 20)

    $textPriority = New-Object System.Windows.Forms.TextBox
    $textPriority.Text = "50"
    $textPriority.Location = New-Object System.Drawing.Point(120, 90)
    $textPriority.Size = New-Object System.Drawing.Size(50, 20)

    $label3 = New-Object System.Windows.Forms.Label
    $label3.Text = "Notizen:"
    $label3.Location = New-Object System.Drawing.Point(10, 120)
    $label3.Size = New-Object System.Drawing.Size(100, 20)

    $textNotes = New-Object System.Windows.Forms.TextBox
    $textNotes.Location = New-Object System.Drawing.Point(10, 145)
    $textNotes.Size = New-Object System.Drawing.Size(370, 50)
    $textNotes.Multiline = $true

    $buttonOK = New-Object System.Windows.Forms.Button
    $buttonOK.Text = "OK"
    $buttonOK.Location = New-Object System.Drawing.Point(220, 200)
    $buttonOK.Size = New-Object System.Drawing.Size(80, 30)

    $buttonOK.Add_Click({
        if ([string]::IsNullOrWhiteSpace($textName.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Datenbankname erforderlich!", "Fehler",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        # Neue Datenbank hinzufügen
        $newDb = @{
            Name = $textName.Text
            Enabled = $checkEnabled.Checked
            BackupType = "FULL"
            IncludeInDifferential = $checkDiff.Checked
            Priority = [int]$textPriority.Text
            Notes = $textNotes.Text
        }

        $config.SelectedDatabases += $newDb

        # Grid aktualisieren
        $dataGridDatabases.Rows.Add(@(
            $newDb.Name,
            $newDb.Enabled,
            $newDb.IncludeInDifferential,
            $newDb.Priority,
            $newDb.Notes
        ))

        $form2.Close()
    })

    $form2.Controls.Add($label1)
    $form2.Controls.Add($textName)
    $form2.Controls.Add($checkEnabled)
    $form2.Controls.Add($checkDiff)
    $form2.Controls.Add($label2)
    $form2.Controls.Add($textPriority)
    $form2.Controls.Add($label3)
    $form2.Controls.Add($textNotes)
    $form2.Controls.Add($buttonOK)

    $form2.ShowDialog()
})

$tabDatabases.Controls.Add($buttonAddDatabase)
$tabDatabases.Controls.Add($buttonRemoveDatabase)

# ==============================================================================
# TAB 2: EINSTELLUNGEN
# ==============================================================================

$labelTdpDir = New-Object System.Windows.Forms.Label
$labelTdpDir.Text = "TDP-Verzeichnis:"
$labelTdpDir.Location = New-Object System.Drawing.Point(10, 10)
$labelTdpDir.Size = New-Object System.Drawing.Size(100, 20)

$textTdpDir = New-Object System.Windows.Forms.TextBox
$textTdpDir.Text = $config.Configuration.TdpDir
$textTdpDir.Location = New-Object System.Drawing.Point(120, 10)
$textTdpDir.Size = New-Object System.Drawing.Size(620, 20)

$labelSqlServer = New-Object System.Windows.Forms.Label
$labelSqlServer.Text = "SQL Server:"
$labelSqlServer.Location = New-Object System.Drawing.Point(10, 40)
$labelSqlServer.Size = New-Object System.Drawing.Size(100, 20)

$textSqlServer = New-Object System.Windows.Forms.TextBox
$textSqlServer.Text = $config.Configuration.SQLServer
$textSqlServer.Location = New-Object System.Drawing.Point(120, 40)
$textSqlServer.Size = New-Object System.Drawing.Size(300, 20)

$labelPassword = New-Object System.Windows.Forms.Label
$labelPassword.Text = "TSM-Passwort:"
$labelPassword.Location = New-Object System.Drawing.Point(10, 70)
$labelPassword.Size = New-Object System.Drawing.Size(100, 20)

$textPassword = New-Object System.Windows.Forms.TextBox
$textPassword.Text = $config.Configuration.TSMPassword
$textPassword.Location = New-Object System.Drawing.Point(120, 70)
$textPassword.Size = New-Object System.Drawing.Size(300, 20)
$textPassword.PasswordChar = '*'

$labelEmail = New-Object System.Windows.Forms.Label
$labelEmail.Text = "Alert-Email:"
$labelEmail.Location = New-Object System.Drawing.Point(10, 100)
$labelEmail.Size = New-Object System.Drawing.Size(100, 20)

$textEmail = New-Object System.Windows.Forms.TextBox
$textEmail.Text = $config.Configuration.AlertEmail
$textEmail.Location = New-Object System.Drawing.Point(120, 100)
$textEmail.Size = New-Object System.Drawing.Size(400, 20)

$tabSettings.Controls.Add($labelTdpDir)
$tabSettings.Controls.Add($textTdpDir)
$tabSettings.Controls.Add($labelSqlServer)
$tabSettings.Controls.Add($textSqlServer)
$tabSettings.Controls.Add($labelPassword)
$tabSettings.Controls.Add($textPassword)
$tabSettings.Controls.Add($labelEmail)
$tabSettings.Controls.Add($textEmail)

# ==============================================================================
# TAB 3: SYSTEM-SETTINGS
# ==============================================================================

$infoSystemSettings = New-Object System.Windows.Forms.Label
$infoSystemSettings.Text = "VORSICHT: Diese Einstellungen werden vom Setup-Wizard verwaltet.`nNur ändern wenn Setup nochmal durchlaufen soll!"
$infoSystemSettings.Location = New-Object System.Drawing.Point(10, 10)
$infoSystemSettings.Size = New-Object System.Drawing.Size(750, 40)
$infoSystemSettings.ForeColor = [System.Drawing.Color]::Red
$tabSystemSettings.Controls.Add($infoSystemSettings)

$labelSQLInstance = New-Object System.Windows.Forms.Label
$labelSQLInstance.Text = "SQL Instance:"
$labelSQLInstance.Location = New-Object System.Drawing.Point(10, 60)
$labelSQLInstance.Size = New-Object System.Drawing.Size(100, 20)
$tabSystemSettings.Controls.Add($labelSQLInstance)

$textSQLInstance = New-Object System.Windows.Forms.TextBox
$textSQLInstance.Text = "YOUR-SQL-SERVER"
$textSQLInstance.Location = New-Object System.Drawing.Point(120, 60)
$textSQLInstance.Size = New-Object System.Drawing.Size(300, 20)
$tabSystemSettings.Controls.Add($textSQLInstance)

$labelSystemPassword = New-Object System.Windows.Forms.Label
$labelSystemPassword.Text = "TSM-Passwort:"
$labelSystemPassword.Location = New-Object System.Drawing.Point(10, 90)
$labelSystemPassword.Size = New-Object System.Drawing.Size(100, 20)
$tabSystemSettings.Controls.Add($labelSystemPassword)

$textSystemPassword = New-Object System.Windows.Forms.TextBox
$textSystemPassword.PasswordChar = '*'
$textSystemPassword.Location = New-Object System.Drawing.Point(120, 90)
$textSystemPassword.Size = New-Object System.Drawing.Size(300, 20)
$tabSystemSettings.Controls.Add($textSystemPassword)

$labelTsmOptFileSystem = New-Object System.Windows.Forms.Label
$labelTsmOptFileSystem.Text = "TSM Opt-File:"
$labelTsmOptFileSystem.Location = New-Object System.Drawing.Point(10, 120)
$labelTsmOptFileSystem.Size = New-Object System.Drawing.Size(100, 20)
$tabSystemSettings.Controls.Add($labelTsmOptFileSystem)

$textTsmOptFileSystem = New-Object System.Windows.Forms.TextBox
$textTsmOptFileSystem.Location = New-Object System.Drawing.Point(120, 120)
$textTsmOptFileSystem.Size = New-Object System.Drawing.Size(300, 20)
$tabSystemSettings.Controls.Add($textTsmOptFileSystem)

$labelTdpConfigFileSystem = New-Object System.Windows.Forms.Label
$labelTdpConfigFileSystem.Text = "TDP Config-File:"
$labelTdpConfigFileSystem.Location = New-Object System.Drawing.Point(10, 150)
$labelTdpConfigFileSystem.Size = New-Object System.Drawing.Size(100, 20)
$tabSystemSettings.Controls.Add($labelTdpConfigFileSystem)

$textTdpConfigFileSystem = New-Object System.Windows.Forms.TextBox
$textTdpConfigFileSystem.Location = New-Object System.Drawing.Point(120, 150)
$textTdpConfigFileSystem.Size = New-Object System.Drawing.Size(300, 20)
$tabSystemSettings.Controls.Add($textTdpConfigFileSystem)

# ==============================================================================
# TAB 4: INFO
# ==============================================================================

$infoText = @"
TDP Backup Plan - Konfigurationstool
Version: 1.0
Datum: 2026-07-08

Diese GUI ermöglicht es Ihnen, die Backup-Konfiguration zu verwalten,
ohne die JSON-Datei direkt zu editieren.

FUNKTIONEN:
✓ Datenbanken hinzufügen/entfernen
✓ Priorität einstellen (höher = früher)
✓ Differential-Backups ein/ausschalten
✓ Notizen für jede Datenbank
✓ TDP-Einstellungen konfigurieren

WORKFLOW:
1. Datenbanken im Tab "Datenbanken" konfigurieren
2. Einstellungen im Tab "Einstellungen" anpassen
3. "Speichern" klicken
4. Agent-Job wird beim nächsten Lauf die neue Config nutzen

Konfigurationsdatei: $ConfigPath
"@

$textInfo = New-Object System.Windows.Forms.TextBox
$textInfo.Multiline = $true
$textInfo.ReadOnly = $true
$textInfo.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$textInfo.Location = New-Object System.Drawing.Point(10, 10)
$textInfo.Size = New-Object System.Drawing.Size(750, 480)
$textInfo.Text = $infoText

$tabInfo.Controls.Add($textInfo)

# ==============================================================================
# BUTTONS UNTEN
# ==============================================================================

$panelButtons = New-Object System.Windows.Forms.Panel
$panelButtons.Dock = [System.Windows.Forms.DockStyle]::Bottom
$panelButtons.Height = 50
$panelButtons.BackColor = [System.Drawing.Color]::LightGray

$buttonSave = New-Object System.Windows.Forms.Button
$buttonSave.Text = "💾 Speichern"
$buttonSave.Location = New-Object System.Drawing.Point(10, 10)
$buttonSave.Size = New-Object System.Drawing.Size(100, 30)
$buttonSave.BackColor = [System.Drawing.Color]::LightGreen
$buttonSave.ForeColor = [System.Drawing.Color]::Black

$buttonCancel = New-Object System.Windows.Forms.Button
$buttonCancel.Text = "Abbrechen"
$buttonCancel.Location = New-Object System.Drawing.Point(120, 10)
$buttonCancel.Size = New-Object System.Drawing.Size(100, 30)

$buttonSave.Add_Click({
    # Daten aus Form aktualisieren
    $config.Configuration.TdpDir = $textTdpDir.Text
    $config.Configuration.SQLServer = $textSqlServer.Text
    $config.Configuration.TSMPassword = $textPassword.Text
    $config.Configuration.AlertEmail = $textEmail.Text

    # Datenbanken aktualisieren
    $config.SelectedDatabases = @()
    foreach ($row in $dataGridDatabases.Rows) {
        $db = @{
            Name = $row.Cells[0].Value
            Enabled = [bool]$row.Cells[1].Value
            BackupType = "FULL"
            IncludeInDifferential = [bool]$row.Cells[2].Value
            Priority = [int]$row.Cells[3].Value
            Notes = $row.Cells[4].Value
        }
        $config.SelectedDatabases += $db
    }

    if (Save-Config -Config $config) {
        $form.Close()
    }
})

$buttonCancel.Add_Click({
    $form.Close()
})

$panelButtons.Controls.Add($buttonSave)
$panelButtons.Controls.Add($buttonCancel)

$form.Controls.Add($tabControl)
$form.Controls.Add($panelButtons)

[void]$form.ShowDialog()
