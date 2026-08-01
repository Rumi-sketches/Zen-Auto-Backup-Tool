# backup.ps1
# Creates a compressed backup of the Zen profile and applies retention.
# Settings come from config.json unless overridden by parameters.
#   powershell -File lib\backup.ps1               # uses config (categories + keep)
#   powershell -File lib\backup.ps1 -Categories appearance,spaces
#   powershell -File lib\backup.ps1 -Quiet        # no output (used by the task)
#   powershell -File lib\backup.ps1 -Yes          # no confirmation prompts
param(
    [string[]]$Categories,
    [string]$ProfilePath,
    [switch]$Quiet,
    [switch]$Yes
)

. "$PSScriptRoot\common.ps1"
$cfg = Get-ZenConfig

function Say($msg, $color = 'Gray') { if (-not $Quiet) { Write-Host $msg -ForegroundColor $color } }

# Accept "a,b,c" as a single string (how the scheduled task passes it) or an array.
if ($Categories) { $Categories = $Categories -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } }
if (-not $Categories) { $Categories = @($cfg.categories) }
if (-not $Categories) { $Categories = @($ZenCategories.Keys) }

if (-not $ProfilePath) { $ProfilePath = Resolve-ZenProfile $cfg }
if (-not $ProfilePath -or -not (Test-Path $ProfilePath)) {
    Write-Host 'No Zen profile found.' -ForegroundColor Red
    Write-ZenLog 'Backup failed: no Zen profile found' 'ERROR'
    exit 1
}

Say "Profile: $ProfilePath" 'Cyan'
if (Test-ZenRunning) {
    Say 'Zen is running. Database files (history, cookies) may miss their most recent changes. Close Zen for a perfect snapshot.' 'Yellow'
}

# Credentials in a plain zip: say it out loud, every time.
$sensitive = @(Get-ZenSensitive $Categories)
if ($sensitive.Count) {
    if ($Quiet) {
        Write-ZenLog ("Backup includes unencrypted credentials: {0}" -f ($sensitive -join ', ')) 'WARN'
    } else {
        Show-ZenSensitiveWarning $Categories | Out-Null
        if (-not $Yes) {
            $ok = Read-Host "`nInclude them anyway? (y/n)"
            if ($ok.Trim().ToLower() -ne 'y') { Write-Host 'Cancelled.'; exit 0 }
        }
    }
}

$stamp     = Get-Date -Format 'yyyy-MM-dd_HHmm'
$stage     = Join-Path $env:TEMP "zenbackup_$stamp"
$profStage = Join-Path $stage 'profile'

# From here on nothing may fail silently: with -Quiet this is the scheduled
# task running with no window, and the log is the only witness.
try {
    New-Item -ItemType Directory -Path $profStage -Force | Out-Null

    $total = 0
    foreach ($cat in $Categories) {
        if (-not $ZenCategories.Contains($cat)) { Say "Unknown category: $cat (skipped)" 'Yellow'; continue }
        $r = Copy-ZenItems -Src $ProfilePath -Dst $profStage -Items $ZenCategories[$cat].items
        $total += $r.Copied
        Say ("  [{0,-11}] {1} items" -f $cat, $r.Copied)
    }

    # The manifest lets restore rewrite absolute paths from the source profile.
    [pscustomobject]@{
        created    = (Get-Date).ToString('s')
        sourcePath = $ProfilePath
        profile    = Split-Path $ProfilePath -Leaf
        categories = $Categories
        version    = $ZenToolVersion
    } | ConvertTo-Json | Set-Content (Join-Path $stage 'manifest.json') -Encoding UTF8

    $backupFolder = Get-BackupFolder $cfg
    if (-not (Test-Path $backupFolder)) { New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null }
    $zip = Join-Path $backupFolder "zen_$stamp.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    } finally {
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    }

    $size = '{0:N1} MB' -f ((Get-Item $zip).Length / 1MB)
    Say "Backup created: $zip ($size, $total items)" 'Green'
    Write-ZenLog ("Backup created: {0} ({1}, {2} items) [{3}]" -f (Split-Path $zip -Leaf), $size, $total, ($Categories -join ','))

    # Retention: keep only the most recent N backups.
    $keep = [int]$cfg.keep
    if ($keep -lt 1) { $keep = 1 }
    $all = @(Get-ChildItem $backupFolder -Filter 'zen_*.zip' | Sort-Object LastWriteTime -Descending)
    if ($all.Count -gt $keep) {
        $all | Select-Object -Skip $keep | ForEach-Object {
            Remove-Item $_.FullName -Force
            Say "  removed old backup: $($_.Name)" 'DarkGray'
            Write-ZenLog "Retention: removed $($_.Name)"
        }
    }
} catch {
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    Write-ZenLog "Backup FAILED: $($_.Exception.Message)" 'ERROR'
    if (-not $Quiet) { Write-Host "Backup failed: $($_.Exception.Message)" -ForegroundColor Red }
    exit 1
}
