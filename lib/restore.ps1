# restore.ps1
# Interactive restore: pick which backup and which categories to restore.
#   powershell -File lib\restore.ps1
#   powershell -File lib\restore.ps1 -Backup zen_2026-06-25_0958.zip -Categories spaces,appearance
param(
    [string]$Backup,
    [string[]]$Categories,
    [string]$ProfilePath
)

. "$PSScriptRoot\common.ps1"
$cfg = Get-ZenConfig
$backupFolder = Get-BackupFolder $cfg

if ($Categories) { $Categories = $Categories -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } }

# 1. choose the backup
$backups = @(Get-ChildItem $backupFolder -Filter 'zen_*.zip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
if (-not $backups) { Write-Host "No backups found in $backupFolder" -ForegroundColor Red; exit 1 }

if ($Backup) {
    $chosen = $backups | Where-Object { $_.Name -eq $Backup -or $_.FullName -eq $Backup } | Select-Object -First 1
    if (-not $chosen) { Write-Host "Backup not found: $Backup" -ForegroundColor Red; exit 1 }
} else {
    Write-Host "`nAvailable backups:`n" -ForegroundColor Cyan
    for ($i = 0; $i -lt $backups.Count; $i++) {
        $b = $backups[$i]
        '{0,2}) {1,-22} {2}  {3:N1} MB' -f ($i + 1), $b.Name, $b.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), ($b.Length / 1MB) | Write-Host
    }
    $sel = Read-Host "`nWhich backup do you want to restore? (number)"
    $n = 0
    if (-not [int]::TryParse($sel.Trim(), [ref]$n)) { Write-Host 'Invalid choice.' -ForegroundColor Red; exit 1 }
    $idx = $n - 1
    if ($idx -lt 0 -or $idx -ge $backups.Count) { Write-Host 'Invalid choice.' -ForegroundColor Red; exit 1 }
    $chosen = $backups[$idx]
}
Write-Host "Selected: $($chosen.Name)" -ForegroundColor Green

# 2. extract and read the manifest
$tmp = Join-Path $env:TEMP ("zenrestore_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
Expand-Archive -Path $chosen.FullName -DestinationPath $tmp -Force
$srcProfile = Join-Path $tmp 'profile'
$manifest   = Get-Content (Join-Path $tmp 'manifest.json') -Raw | ConvertFrom-Json
$oldPath    = $manifest.sourcePath
$available  = @($manifest.categories)

# 3. choose the categories
if (-not $Categories) {
    Write-Host "`nCategories in this backup:`n" -ForegroundColor Cyan
    for ($i = 0; $i -lt $available.Count; $i++) {
        $c = $available[$i]
        $d = if ($ZenCategories.Contains($c)) { $ZenCategories[$c].desc } else { '' }
        '{0,2}) {1,-11} {2}' -f ($i + 1), $c, $d | Write-Host
    }
    Write-Host "`n  Enter = appearance + shortcuts + spaces + preferences   |   'all' = everything" -ForegroundColor DarkGray
    $sel = Read-Host 'Which ones do you want to restore? (numbers separated by commas)'
    if ([string]::IsNullOrWhiteSpace($sel)) {
        $Categories = @('appearance', 'shortcuts', 'spaces', 'preferences') | Where-Object { $available -contains $_ }
    } elseif ($sel.Trim().ToLower() -eq 'all') {
        $Categories = $available
    } else {
        $Categories = $sel -split ',' | ForEach-Object {
            $n = [int]($_.Trim()) - 1
            if ($n -ge 0 -and $n -lt $available.Count) { $available[$n] }
        }
    }
}
if (-not $Categories) { Write-Host 'No categories selected.' -ForegroundColor Red; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue; exit 1 }

# 4. target profile
if (-not $ProfilePath) { $ProfilePath = Resolve-ZenProfile $cfg }
if (-not $ProfilePath) {
    Write-Host 'No Zen profile found.' -ForegroundColor Red
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Host "`nTarget profile: $ProfilePath" -ForegroundColor Cyan
Write-Host "Restoring: $($Categories -join ', ')" -ForegroundColor Cyan

# 5. Zen must be closed
if (Test-ZenRunning) {
    Write-Host 'Zen is running. Close it completely and run the restore again.' -ForegroundColor Red
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
$ok = Read-Host "`nProceed? The selected files will be overwritten (y/n)"
if ($ok.Trim().ToLower() -ne 'y') { Write-Host 'Cancelled.'; Remove-Item $tmp -Recurse -Force; exit 0 }

# 6. copy
if (-not (Test-Path $ProfilePath)) { New-Item -ItemType Directory -Path $ProfilePath -Force | Out-Null }
foreach ($cat in $Categories) {
    if (-not $ZenCategories.Contains($cat)) { continue }
    $r = Copy-ZenItems -Src $srcProfile -Dst $ProfilePath -Items $ZenCategories[$cat].items
    Write-Host ("  [{0,-11}] {1} restored" -f $cat, $r.Copied) -ForegroundColor Gray
}

# 7. fix prefs/paths/icons and remove user.js
if ($Categories -contains 'preferences') {
    Repair-ZenProfile -TargetProfile $ProfilePath -OldProfilePath $oldPath
} else {
    $uj = Join-Path $ProfilePath 'user.js'
    if (Test-Path $uj) { Remove-Item $uj -Force }
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "`nDone. You can open Zen now." -ForegroundColor Green
