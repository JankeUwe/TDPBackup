#Requires -Version 5.1
# ==============================================================================
# New-TdpAgentProxy.ps1 - SQL-Agent-Proxy fuer den TDP-Backup-Job
# ==============================================================================
# Ersatz fuer xp_cmdshell: Der Job-Step laeuft als CmdExec-Step, aber NICHT
# unter dem SQL-Agent-Dienstkonto, sondern unter einem eigenen Windows-Konto
# (Least Privilege). Dieses Skript legt dafuer an:
#   1. SQL-Credential  (Windows-Konto + Passwort, verschluesselt in master)
#   2. Agent-Proxy     (verweist auf das Credential)
#   3. Freigabe des Proxys fuer das Subsystem CmdExec
#   4. optional: Windows-Login fuer das Konto (+ optional sysadmin)
#
# 02_Create_Agent_Job.sql erkennt den Proxy automatisch und haengt ihn an den
# Job-Step. Das Passwort steht nirgends im Klartext (keine Datei, kein Log,
# keine Kommandozeile), es wird nur als SQL-Parameter uebertragen.
#
# USAGE:
#   .\New-TdpAgentProxy.ps1 -SQLInstance "<SQLInstance>"
#   .\New-TdpAgentProxy.ps1 -SQLInstance "<SQLInstance>" -CreateLogin -GrantSysadmin
#
# WICHTIG: TdpBackup.config (TSM-Passwort) ist DPAPI-verschluesselt und nur
# von dem Windows-Konto lesbar, das Setup-TdpBackup.ps1 ausgefuehrt hat.
# Setup daher einmalig ALS PROXY-KONTO ausfuehren:
#   runas /user:<DOMAIN\svc_tdpbackup> "powershell.exe -File Setup-TdpBackup.ps1"
# ==============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$SQLInstance,

    # Windows-Konto, unter dem der Job-Step laufen soll (DOMAIN\Konto)
    [System.Management.Automation.PSCredential]$ProxyCredential,

    [string]$CredentialName = "TDP_Backup_Credential",
    [string]$ProxyName = "TDP_Backup_Proxy",

    # Windows-Login fuer das Proxy-Konto anlegen (Backup-TdpFull.ps1 und
    # tdpsqlc.exe verbinden sich per Integrated Security als dieses Konto)
    [switch]$CreateLogin,

    # Login zusaetzlich in sysadmin aufnehmen (von TDP for SQL in der Regel
    # vorausgesetzt, gegen die IBM-Doku der eingesetzten Version pruefen)
    [switch]$GrantSysadmin,

    # Optional: SQL-Authentifizierung fuer die Verbindung (sonst Windows-Auth)
    [System.Management.Automation.PSCredential]$SqlCredential
)

$ErrorActionPreference = "Stop"

if ($GrantSysadmin -and -not $CreateLogin) {
    throw "-GrantSysadmin setzt -CreateLogin voraus."
}

if ($null -eq $ProxyCredential) {
    $ProxyCredential = Get-Credential -Message "Windows-Konto fuer den TDP-Backup-Job (DOMAIN\Konto)"
    if ($null -eq $ProxyCredential) { throw "Abgebrochen: kein Konto angegeben." }
}

$identity = $ProxyCredential.UserName
if ($identity -notmatch '\\') {
    throw "Konto muss im Format DOMAIN\Konto bzw. COMPUTER\Konto angegeben werden: '$identity'"
}

# ------------------------------------------------------------------------------
# Verbindung
# ------------------------------------------------------------------------------
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$builder["Data Source"] = $SQLInstance
$builder["Initial Catalog"] = "master"
$builder["Connect Timeout"] = 30
if ($null -ne $SqlCredential) {
    $builder["User ID"] = $SqlCredential.UserName
    $builder["Password"] = $SqlCredential.GetNetworkCredential().Password
    $builder["TrustServerCertificate"] = $true
}
else {
    $builder["Integrated Security"] = $true
}

$connection = New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)

function Invoke-ProxySql {
    param(
        [string]$Sql,
        [hashtable]$Parameters = @{}
    )
    $cmd = $connection.CreateCommand()
    $cmd.CommandText = $Sql
    $cmd.CommandTimeout = 60
    foreach ($key in $Parameters.Keys) {
        $p = $cmd.Parameters.Add("@$key", [System.Data.SqlDbType]::NVarChar, 4000)
        $p.Value = $Parameters[$key]
    }
    [void]$cmd.ExecuteNonQuery()
}

# CREATE/ALTER CREDENTIAL akzeptiert keine Parameter direkt, daher serverseitig
# per dynamischem SQL aus den Parametern zusammengesetzt (Quotes maskiert).
$sqlCredential = @"
DECLARE @sql nvarchar(max);
SET @sql = CASE WHEN EXISTS (SELECT 1 FROM sys.credentials WHERE name = @cred)
                THEN N'ALTER' ELSE N'CREATE' END
         + N' CREDENTIAL ' + QUOTENAME(@cred)
         + N' WITH IDENTITY = N''' + REPLACE(@identity, N'''', N'''''')
         + N''', SECRET = N''' + REPLACE(@secret, N'''', N'''''') + N''';';
EXEC sys.sp_executesql @sql;
"@

$sqlProxy = @"
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysproxies WHERE name = @proxy)
    EXEC msdb.dbo.sp_add_proxy
        @proxy_name = @proxy,
        @credential_name = @cred,
        @enabled = 1,
        @description = N'TDP Backup: CmdExec-Step ohne xp_cmdshell, eigenes Windows-Konto';
ELSE
    EXEC msdb.dbo.sp_update_proxy @proxy_name = @proxy, @credential_name = @cred, @enabled = 1;

IF NOT EXISTS (
    SELECT 1
    FROM msdb.dbo.sysproxysubsystem ps
    JOIN msdb.dbo.sysproxies p     ON p.proxy_id = ps.proxy_id
    JOIN msdb.dbo.syssubsystems s  ON s.subsystem_id = ps.subsystem_id
    WHERE p.name = @proxy AND s.subsystem = N'CmdExec')
    EXEC msdb.dbo.sp_grant_proxy_to_subsystem @proxy_name = @proxy, @subsystem_name = N'CmdExec';
"@

$sqlLogin = @"
DECLARE @sql nvarchar(max);
IF SUSER_ID(@identity) IS NULL
BEGIN
    SET @sql = N'CREATE LOGIN ' + QUOTENAME(@identity) + N' FROM WINDOWS WITH DEFAULT_DATABASE = [master];';
    EXEC sys.sp_executesql @sql;
END
"@

$sqlSysadmin = @"
IF IS_SRVROLEMEMBER(N'sysadmin', @identity) = 0
BEGIN
    DECLARE @sql nvarchar(max) = N'ALTER SERVER ROLE [sysadmin] ADD MEMBER ' + QUOTENAME(@identity) + N';';
    EXEC sys.sp_executesql @sql;
END
"@

Write-Host ""
Write-Host "========== TDP Backup - Agent-Proxy =========="
Write-Host "Instance:   $SQLInstance"
Write-Host "Konto:      $identity"
Write-Host "Credential: $CredentialName"
Write-Host "Proxy:      $ProxyName"
Write-Host ""

try {
    $connection.Open()

    Invoke-ProxySql -Sql $sqlCredential -Parameters @{
        cred     = $CredentialName
        identity = $identity
        secret   = $ProxyCredential.GetNetworkCredential().Password
    }
    Write-Host "  ✓ Credential [$CredentialName] angelegt/aktualisiert" -ForegroundColor Green

    Invoke-ProxySql -Sql $sqlProxy -Parameters @{ proxy = $ProxyName; cred = $CredentialName }
    Write-Host "  ✓ Proxy [$ProxyName] fuer Subsystem CmdExec freigegeben" -ForegroundColor Green

    if ($CreateLogin) {
        Invoke-ProxySql -Sql $sqlLogin -Parameters @{ identity = $identity }
        Write-Host "  ✓ Login [$identity] vorhanden" -ForegroundColor Green
    }
    if ($GrantSysadmin) {
        Invoke-ProxySql -Sql $sqlSysadmin -Parameters @{ identity = $identity }
        Write-Host "  ✓ Login [$identity] ist Mitglied in sysadmin" -ForegroundColor Green
    }
}
catch {
    Write-Error "Proxy-Einrichtung fehlgeschlagen: $($_.Exception.Message)"
    exit 1
}
finally {
    $connection.Dispose()
}

Write-Host ""
Write-Host "Naechste Schritte:"
Write-Host "  1. Agent-Job (neu) anlegen, der Proxy wird automatisch verwendet:"
Write-Host "     sqlcmd -S $SQLInstance -i 02_Create_Agent_Job.sql"
Write-Host "  2. Setup einmalig ALS PROXY-KONTO ausfuehren (DPAPI-Bindung TSM-Passwort):"
Write-Host "     runas /user:$identity `"powershell.exe -File Setup-TdpBackup.ps1`""
Write-Host "  3. Konto braucht Lesen auf das Skriptverzeichnis und TdpBackup.config,"
Write-Host "     Schreiben auf 03_Log. KEIN lokaler Administrator noetig."
if (-not $CreateLogin) {
    Write-Host "  4. SQL-Login fuer $identity fehlt evtl. noch (-CreateLogin)." -ForegroundColor Yellow
}
Write-Host ""
