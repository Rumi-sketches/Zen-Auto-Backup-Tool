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
    Write-Host "`n  Enter = the most recent one" -ForegroundColor DarkGray
    $n = Read-ZenInt -Prompt 'Which backup do you want to restore? (number)' -Min 1 -Max $backups.Count -Default 1
    $chosen = $backups[$n - 1]
}
Write-Host "Selected: $($chosen.Name)" -ForegroundColor Green

# Everything below runs inside try/finally: the temp folder holds a full copy of
# the profile, credentials included, and must not survive whatever goes wrong.
$tmp = Join-Path $env:TEMP ("zenrestore_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    # 2. extract and read the manifest
    try {
        Expand-Archive -Path $chosen.FullName -DestinationPath $tmp -Force
    } catch {
        Write-Host "Could not open '$($chosen.Name)': $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'The file may be corrupted or still being written.' -ForegroundColor Red
        exit 1
    }

    $manifestPath = Join-Path $tmp 'manifest.json'
    $manifest     = $null
    if (Test-Path $manifestPath) {
        try { $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json } catch { }
    }
    if (-not $manifest -or -not $manifest.categories) {
        Write-Host "`n'$($chosen.Name)' has no valid manifest.json." -ForegroundColor Red
        Write-Host 'This zip was not created by the Zen Backup Tool, so there is nothing safe to restore from it.' -ForegroundColor Red
        exit 1
    }

    $srcProfile = Join-Path $tmp 'profile'
    $oldPath    = $manifest.sourcePath
    $available  = @($manifest.categories)

    # 3. choose the categories
    if (-not $Categories) {
        Write-Host "`nCategories in this backup:`n" -ForegroundColor Cyan
        for ($i = 0; $i -lt $available.Count; $i++) {
            $c = $available[$i]
            $d = if ($ZenCategories.Contains($c)) { $ZenCategories[$c].desc } else { '' }
            $s = if (Test-ZenSensitive $c) { '(!)' } else { '   ' }
            '{0,2}) {1} {2,-11} {3}' -f ($i + 1), $s, $c, $d | Write-Host
        }
        Write-Host "`n  Numbers (1,3), ranges (1-4) or names   |   Enter = appearance + shortcuts + spaces + preferences   |   'all' = everything" -ForegroundColor DarkGray
        $default = @('appearance', 'shortcuts', 'spaces', 'preferences') | Where-Object { $available -contains $_ }
        $Categories = Read-ZenSelection -Prompt 'Which ones do you want to restore?' -Options $available -Default $default
    }
    if (-not $Categories) { Write-Host 'No categories selected.' -ForegroundColor Red; exit 1 }

    # 4. target profile
    if (-not $ProfilePath) { $ProfilePath = Resolve-ZenProfile $cfg }
    if (-not $ProfilePath) {
        Write-Host 'No Zen profile found. Open Zen once so it creates one, close it, then try again.' -ForegroundColor Red
        exit 1
    }
    Write-Host "`nTarget profile: $ProfilePath" -ForegroundColor Cyan
    Write-Host "Restoring: $($Categories -join ', ')" -ForegroundColor Cyan

    # 5. Zen must be closed
    if (Test-ZenRunning) {
        Write-Host 'Zen is running. Close it completely and run the restore again.' -ForegroundColor Red
        exit 1
    }
    $ok = Read-Host "`nProceed? The selected files will be overwritten (y/n)"
    if ($ok.Trim().ToLower() -ne 'y') { Write-Host 'Cancelled.'; exit 0 }

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

    Write-Host "`nDone. You can open Zen now." -ForegroundColor Green
    Write-ZenLog "Restored $($chosen.Name) [$($Categories -join ',')] into $ProfilePath"
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
