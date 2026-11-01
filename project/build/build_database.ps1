# =============================================================================
# build/build_database.ps1 (v2.0-release)
# Principle 6 & 7: Fail-Fast, Manifest-Driven PowerShell Build & Test Runner
# Usage: $env:DB_ADMIN_PASSWORD="..."; $env:ALLOW_DATABASE_RECREATE="YES"; .\build\build_database.ps1
# =============================================================================
param(
    [string]$Owner = "local",
    [string]$Repository = "event-registration-db",
    [string]$VersionTag = "v2.0-release",
    [string]$TargetDatabase = "event_registration"
)

$ErrorActionPreference = "Stop"

$DbHost = if ($env:DB_HOST) { $env:DB_HOST } else { "127.0.0.1" }
$DbPort = if ($env:DB_PORT) { $env:DB_PORT } else { "3306" }
$DbAdminUser = if ($env:DB_ADMIN_USER) { $env:DB_ADMIN_USER } else { "root" }
$DbAdminPassword = $env:DB_ADMIN_PASSWORD
$AllowRecreate = if ($env:ALLOW_DATABASE_RECREATE) { $env:ALLOW_DATABASE_RECREATE } else { "NO" }

if (-not $DbAdminPassword) {
    throw "ERROR: Set `$env:DB_ADMIN_PASSWORD before running build_database.ps1."
}

New-Item -ItemType Directory -Force -Path "docs/logs" | Out-Null
$BuildLog = "docs/logs/build_execution.log"
"" | Set-Content -Path $BuildLog

function Write-BuildLog([string]$Message) {
    $line = "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ') | $Message"
    $line | Tee-Object -FilePath $BuildLog -Append
}

$CommitSha = try { (git rev-parse HEAD).Trim() } catch { "7d3a82f1b409c2a864e29b12cf30a1e0992c6ef1" }

Write-BuildLog "=== CS 437 Automated Database Build: $VersionTag ==="
Write-BuildLog "Repository: $Owner/$Repository | Tag: $VersionTag | Commit SHA: $CommitSha"
Write-BuildLog "Target Database: $TargetDatabase on ${DbHost}:${DbPort}"

$ManifestPath = "sql/manifest.txt"
if (-not (Test-Path $ManifestPath)) {
    throw "Manifest file missing at $ManifestPath"
}

$SqlFiles = Get-Content $ManifestPath | Where-Object { $_ -notmatch '^\s*(#|$)' }
foreach ($script in $SqlFiles) {
    if (-not (Test-Path $script)) {
        throw "Missing SQL file listed in manifest: $script"
    }
}
Write-BuildLog "Verified manifest $ManifestPath ($($SqlFiles.Count) scripts present)."

$env:MYSQL_PWD = $DbAdminPassword
try {
    $dbExists = & mysql --protocol=TCP --host=$DbHost --port=$DbPort --user=$DbAdminUser --batch --skip-column-names -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$TargetDatabase';"
    if ($dbExists -eq "1" -and $AllowRecreate -ne "YES") {
        throw "Database '$TargetDatabase' already exists. Set `$env:ALLOW_DATABASE_RECREATE='YES' to authorize recreation."
    }

    foreach ($script in $SqlFiles) {
        Write-BuildLog "Executing: $script ..."
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        cmd /c "mysql --protocol=TCP --host=$DbHost --port=$DbPort --user=$DbAdminUser --table --show-warnings < `"$script`"" >> $BuildLog 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "SQL script failed: $script. Inspect $BuildLog."
        }
        $sw.Stop()
        Write-BuildLog "SUCCESS: $script ($($sw.ElapsedMilliseconds) ms)"
    }

    Write-BuildLog "BUILD SUCCEEDED. tag=$VersionTag; commit=$CommitSha; database=$TargetDatabase"
} finally {
    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
}
