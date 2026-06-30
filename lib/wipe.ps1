# wipe.ps1
# Deletes Zen's data so you can reinstall from scratch.
# By default it takes a full backup first, then closes Zen and removes the data.
#   powershell -File lib\wipe.ps1
#   powershell -File lib\wipe.ps1 -NoBackup
#   powershell -File lib\wipe.ps1 -Force
param(
    [switch]$NoBackup,
    [switch]$Force
)

. "$PSScriptRoot\common.ps1"
$cfg = Get-ZenConfig

$targets = @(
    (Join-Path $env:APPDATA      'zen'),   # profile and data
    (Join-Path $env:LOCALAPPDATA 'zen')    # cache and installer files
)

Write-Host "These folders will be deleted:" -ForegroundColor Cyan
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
Write-Host "Backups in $(Get-BackupFolder $cfg) are not touched." -ForegroundColor DarkGray

if (-not $NoBackup) {
    if (Resolve-ZenProfile $cfg) {
        Write-Host "`nTaking a full safety backup first..." -ForegroundColor Yellow
        & "$PSScriptRoot\backup.ps1" -Categories ($ZenCategories.Keys -join ',')
    } else {
        Write-Host "`nNo profile to back up, skipping." -ForegroundColor DarkGray
    }
}

if (-not $Force) {
    $ok = Read-Host "`nConfirm deletion? (y/n)"
    if ($ok.Trim().ToLower() -ne 'y') { Write-Host 'Cancelled.'; exit 0 }
}

$proc = Get-Process -Name 'zen' -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "Closing Zen..." -ForegroundColor Yellow
    $proc | Stop-Process -Force
    $proc | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
}

foreach ($t in $targets) {
    if (Test-Path $t) {
        try {
            Remove-Item $t -Recurse -Force -ErrorAction Stop
            Write-Host "  deleted: $t" -ForegroundColor Green
        } catch {
            Write-Warning "  Could not delete '$t': $($_.Exception.Message)"
            Write-Warning "  (Is Zen or another process still using it? Close everything and try again.)"
        }
    }
}

Write-Host "`nDone. Zen is clean. Reinstall it, open and close it once, then run a restore." -ForegroundColor Green
