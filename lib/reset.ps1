# reset.ps1
# Resets Zen to factory settings: removes all of its data so the next launch
# behaves like a fresh download. Zen itself stays installed.
#   powershell -File lib\reset.ps1
#   powershell -File lib\reset.ps1 -NoBackup
#   powershell -File lib\reset.ps1 -Force
param(
    [switch]$NoBackup,
    [switch]$Force
)

. "$PSScriptRoot\common.ps1"
$cfg = Get-ZenConfig
$backupFolder = Get-BackupFolder $cfg

$targets = @(
    (Join-Path $env:APPDATA      'zen'),   # profile and data
    (Join-Path $env:LOCALAPPDATA 'zen')    # cache and installer files
)

Write-Host "Reset Zen to factory settings" -ForegroundColor Cyan
Write-Host "Zen stays installed. Only its data is removed, so the next launch"
Write-Host "starts from scratch, exactly like a fresh download."

Write-Host "`nThese folders will be deleted:" -ForegroundColor Cyan
$totMB = 0
foreach ($t in $targets) {
    if (Test-Path $t) {
        $mb = ((Get-ChildItem $t -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB
        $totMB += $mb
        "  {0,-45} {1:N1} MB" -f $t, $mb | Write-Host
    } else {
        "  {0,-45} (not present)" -f $t | Write-Host
    }
}
Write-Host ("Total: {0:N1} MB" -f $totMB) -ForegroundColor Cyan
Write-Host "Backups in $backupFolder are not touched." -ForegroundColor DarkGray

# ---------------------------------------------------------------- safety backup
$existing = @(Get-ChildItem $backupFolder -Filter 'zen_*.zip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
if ($existing.Count) {
    Write-Host ("`nYou already have {0} backup(s). Most recent: {1} ({2})." -f `
        $existing.Count, $existing[0].Name, $existing[0].LastWriteTime.ToString('yyyy-MM-dd HH:mm')) -ForegroundColor DarkGray
} else {
    Write-Host "`nYou have no backups yet." -ForegroundColor Yellow
}

$takeBackup = $false
if (-not $NoBackup) {
    if (-not (Resolve-ZenProfile $cfg)) {
        Write-Host "`nNo Zen profile found, there is nothing to back up." -ForegroundColor DarkGray
    } else {
        Write-Host "`nBefore resetting:"
        Write-Host " 1) Take a full safety backup now  (recommended)"
        Write-Host " 2) Skip it and reset straight away"
        $takeBackup = ((Read-Host "`nChoice").Trim() -ne '2')

        if (-not $takeBackup) {
            Write-Host "`nWithout a backup you permanently lose:" -ForegroundColor Yellow
            foreach ($k in $ZenCategories.Keys) {
                "    - {0,-11} {1}" -f $k, $ZenCategories[$k].desc | Write-Host -ForegroundColor Yellow
            }
            if ($existing.Count) {
                Write-Host ("  You could still fall back to {0}, from {1}." -f `
                    $existing[0].Name, $existing[0].LastWriteTime.ToString('yyyy-MM-dd HH:mm')) -ForegroundColor DarkGray
            } else {
                Write-Host "  No previous backup exists: this is unrecoverable." -ForegroundColor Red
            }
            if (-not $Force) {
                $ok = Read-Host "`nReset without a backup? (y/n)"
                if ($ok.Trim().ToLower() -ne 'y') { Write-Host 'Cancelled.'; exit 0 }
            }
        }
    }
}

if ($takeBackup) {
    Write-Host "`nTaking a full safety backup first..." -ForegroundColor Yellow
    & "$PSScriptRoot\backup.ps1" -Categories ($ZenCategories.Keys -join ',')
}

# -------------------------------------------------------------------- deletion
if (-not $Force) {
    $ok = Read-Host "`nConfirm reset? (y/n)"
    if ($ok.Trim().ToLower() -ne 'y') { Write-Host 'Cancelled.'; exit 0 }
}

$proc = Get-Process -Name 'zen' -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "Closing Zen..." -ForegroundColor Yellow
    $proc | Stop-Process -Force
    $proc | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
}

$failed = $false
foreach ($t in $targets) {
    if (Test-Path $t) {
        try {
            Remove-Item $t -Recurse -Force -ErrorAction Stop
            Write-Host "  deleted: $t" -ForegroundColor Green
        } catch {
            $failed = $true
            Write-Warning "  Could not delete '$t': $($_.Exception.Message)"
            Write-Warning "  (Is Zen or another process still using it? Close everything and try again.)"
        }
    }
}
if ($failed) { exit 1 }

Write-Host "`nDone. Zen is back to factory settings." -ForegroundColor Green

# ------------------------------------------------------------------- what now
if ($Force) { exit 0 }

$zenExe = Find-ZenExe

# Launch Zen, or tell the user to do it by hand when the exe is not found.
function Start-Zen {
    if ($zenExe) {
        Write-Host "Opening Zen..." -ForegroundColor Yellow
        Start-Process $zenExe
        return
    }
    Write-Host "Could not find zen.exe. Please open Zen yourself." -ForegroundColor Yellow
}

# Zen writes the new profile a moment after launch. Wait for prefs.js to show
# up, otherwise a restore started right away would have nothing to restore into.
function Wait-ZenProfile {
    param([int]$TimeoutSeconds = 180)
    Write-Host "Waiting for Zen to create the new profile..." -ForegroundColor DarkGray
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $p = Get-ZenProfiles | Where-Object { Test-Path (Join-Path $_.Path 'prefs.js') } | Select-Object -First 1
        if ($p) {
            Write-Host "  New profile ready: $($p.Name)" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds 2
    }
    Write-Host "  Timed out waiting for the profile." -ForegroundColor Yellow
    return $false
}

Write-Host "`nWhat now?"
Write-Host " 1) Open Zen now  (fresh start, first-run experience)"
Write-Host " 2) Open Zen, then restore a backup"
Write-Host " 0) Nothing, back to the menu"

switch ((Read-Host "`nChoice").Trim()) {
    '1' { Start-Zen }
    '2' {
        Write-Host "`nHow this works:" -ForegroundColor Cyan
        Write-Host "  Zen opens first, because a backup can only be restored into an existing"
        Write-Host "  profile and the reset just removed it. Go through the first-run screens,"
        Write-Host "  then close Zen completely: the restore starts by itself right after."
        Wait-ZenCountdown -Seconds 6 -Message 'Opening Zen in'

        Start-Zen
        if (Wait-ZenProfile) {
            Write-Host "`nNow close Zen completely to continue (Ctrl+C here to stop)." -ForegroundColor Yellow
            while (Test-ZenRunning) { Start-Sleep -Seconds 2 }
            Write-Host "Zen closed." -ForegroundColor Green
            & "$PSScriptRoot\restore.ps1"
        } else {
            Write-Host "Open Zen once, close it, then run a restore from the main menu." -ForegroundColor Yellow
        }
    }
    default { }
}
