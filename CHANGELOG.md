# TDP Backup System — Changelog

## [Unreleased] — 2026-08-11 (2)

### Fix: hardcoded server names and email addresses removed

`SRPSDSQL011`/`012`/`013` and `admin@bank.de` appeared as defaults and examples throughout the
scripts, SQL setup, and docs. Replaced with `<SQLInstance>`-style placeholders in docs/examples;
removed the (unused) `-SqlServer` parameter from `Backup-TdpFull.ps1` and the unused `-SQLSERVer`
parameter from `Setup-TdpBackup.ps1` instead of giving them a hardcoded default — the instance
name now always comes from `TdpBackup.config` (`Setup-TdpBackup.ps1`) or must be typed into the
GUI, never silently defaults to a specific customer's server.

### Fix: disabling a database in the JSON did not stop its scheduled FULL backup

`Get-DatabasesForFullBackup` selected databases via `BackupStatus.IsInBackupPlan`, a flag that is
only ever set once (at initial setup / auto-discovery) and never updated afterwards. Disabling a
database (`Enabled: false` in `BackupPlan.json`) correctly removed it from differential backups and
from special handling, but it kept receiving FULL backups every scheduled FULL day forever. Now
joins `TDP_BackupPlan` and filters on the live `Enabled` flag, same as
`Get-DatabasesForDifferentialBackup` already did.

### Fix: databases added only via the JSON were never backed up

`Sync-JsonToDatabase` only wrote to `TDP_BackupPlan`. The special-handling step that gives new
databases their first FULL backup is driven by the view `v_DatabasesWithoutFullBackup`, which
starts from `BackupStatus` — a table that only gets a row for a database via the initial setup
scan or `sp_DiscoverNewDatabases`. A database added purely through `BackupPlan.json` (the
documented "simple" way per README) never got a `BackupStatus` row and so was silently never
backed up. `Sync-JsonToDatabase` now also inserts a `BackupStatus` stub row for any enabled
database that doesn't have one yet.

### Fix: "Ausgewählte entfernen" button in Configure-BackupPlan.ps1 did nothing

The remove-selected-database button in the GUI's "Datenbanken" tab had no click handler. Selecting
rows and clicking it had no effect. Wired it up to remove the selected grid rows.

## [Unreleased] — 2026-08-11

### Fix: PowerShell 5.1 compatibility

`Backup-TdpFull.ps1`, `Setup-TdpBackup.ps1`, and the `Modules/*.psm1` scripts used the
null-coalescing (`??`) and ternary (`?:`) operators, which only exist in PowerShell 7+. The
daily backup job is invoked via `powershell.exe` (PS 5.1 on a standard Windows Server), so the
script failed to parse and never ran. Replaced with `if`/`else` throughout, added
`#Requires -Version 5.1` to every script and module.

### Fix: TSM password stored in plaintext

`Setup-TdpBackup.ps1` stored `TSMPassword` as a plain string in `TdpBackup.config` via
`Export-Clixml`. Now converted to a `SecureString` (DPAPI-encrypted, user/machine-bound) before
storage, and only decrypted in `TdpBackupHelper.psm1` immediately before the `tdpsqlc.exe` call.

### Fix: missing UTF-8 BOM broke PowerShell 5.1 parsing

None of the `.ps1`/`.psm1` files had a UTF-8 BOM. PowerShell 5.1 reads BOM-less script files
using the system ANSI code page, which mangled the emoji/umlaut characters in the scripts and
broke the parser in unrelated places. Added a UTF-8 BOM to all six scripts/modules.

### Fix: `Backup-TdpFull.ps1` never ran the scheduled FULL/DIFF backups when `AllowSpecialHandling` was disabled

The `if ($allowSpecialHandling) { ... }` block opened in the special-handling step was never
closed, so the regular FULL-backup step (Sunday), the DIFF-backup step (Mon-Sat), the final
report, and `$dbConnection.Close()` were all nested inside it by accident. With
`AllowSpecialHandling: false` (the config used by "Szenario 2: Maximale Verfügbarkeit" in
ARCHITECTURE.md), no scheduled backup would ever run. Added the missing closing brace so the
special-handling step and the regular FULL/DIFF steps run as the documented independent steps.

## [1.0] — 2026-07-08

### Initial release

SQL setup, PowerShell scripts, and GUI configuration tool for TDP-based backups. Scenario-based
backup strategy with configurable FULL/DIFF days per customer. Setup wizard, system config, and a
Settings tab in the GUI — production ready. Comprehensive admin handbook covering daily tasks,
monitoring, troubleshooting, and FAQ. Architecture: one SQL Agent job covers all scenarios,
replacing two separate jobs.

---
*Reconstructed from commit history in the parent `C:\CCM` repository — this tool does not have its
own separate git repository.*
