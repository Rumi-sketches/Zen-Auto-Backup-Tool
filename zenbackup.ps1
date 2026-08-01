# zenbackup.ps1
# Single entry point for the Zen Backup Tool. Run it or double click ZenBackup.bat.

. "$PSScriptRoot\lib\common.ps1"

# Create config.json from defaults on first run.
if (-not (Test-Path $ConfigPath)) { Save-ZenConfig (New-DefaultConfig) }

function Pause-Key { Read-Host "`nPress Enter to continue" | Out-Null }

function Show-Header {
    Clear-Host
    $cfg = Get-ZenConfig
    $prof = Resolve-ZenProfile $cfg
    $sched = $cfg.schedule.frequency
    if ($sched -eq 'daily')   { $sched = "daily at $($cfg.schedule.time)" }
    if ($sched -eq 'weekly')  { $sched = "weekly ($($cfg.schedule.weekday)) at $($cfg.schedule.time)" }
    if ($sched -eq 'hourly')  { $sched = "every $($cfg.schedule.everyHours)h" }
    # Both rules are derived from one width so they always line up.
    $width = 60
    $title = "Zen Backup Tool v$ZenToolVersion  -  by @Rumi-sketches"
    $side  = [math]::Max(0, $width - $title.Length - 2)
    Write-Host ("{0} {1} {2}" -f ('=' * [math]::Floor($side / 2)), $title, ('=' * [math]::Ceiling($side / 2))) -ForegroundColor Cyan
    Write-Host (" Profile : {0}" -f $(if ($prof) { Split-Path $prof -Leaf } else { 'not found' }))
    Write-Host (" Backups : {0}" -f (Get-BackupFolder $cfg))
    $auto = " Auto    : {0}   keep {1}   [{2}]" -f $sched, $cfg.keep, ($cfg.categories -join ',')
    $sens = @(Get-ZenSensitive @($cfg.categories))
    if ($sens.Count -and $cfg.schedule.frequency -ne 'disabled') {
        Write-Host $auto -ForegroundColor Yellow
        Write-Host ("           includes {0}, stored unencrypted" -f ($sens -join ' and ')) -ForegroundColor Yellow
    } else {
        Write-Host $auto
    }
    Write-Host ('=' * $width) -ForegroundColor Cyan
}

function Pick-Categories {
    param([string[]]$Current)
    $keys = @($ZenCategories.Keys)
    Write-Host "`nCategories:`n"
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $mark = if ($Current -contains $keys[$i]) { '[x]' } else { '[ ]' }
        $sens = Test-ZenSensitive $keys[$i]
        $line = '{0,2}) {1} {2} {3,-11} {4}' -f ($i + 1), $mark, $(if ($sens) { '(!)' } else { '   ' }), $keys[$i], $ZenCategories[$keys[$i]].desc
        if ($sens) { Write-Host $line -ForegroundColor Yellow } else { Write-Host $line }
    }
    Write-Host "`n  (!) credentials: stored unencrypted inside the zip, off by default" -ForegroundColor DarkYellow
    Write-Host "  Numbers (1,3), ranges (1-4) or names   |   Enter = keep current   |   'all' = everything" -ForegroundColor DarkGray
    return Read-ZenSelection -Prompt 'Type the ones you want' -Options $keys -Default $Current
}

function Menu-BackupNow {
    Show-Header
    Write-Host "`n 1) Full backup (everything)"
    Write-Host " 2) Backup using my saved categories"
    Write-Host " 3) Pick categories for this backup"
    Write-Host " 0) Back"
    switch (Read-Host "`nChoice") {
        '1' { & "$PSScriptRoot\lib\backup.ps1" -Categories ($ZenCategories.Keys -join ','); Pause-Key }
        '2' { & "$PSScriptRoot\lib\backup.ps1"; Pause-Key }
        '3' {
            $cats = Pick-Categories @()
            if ($cats) { & "$PSScriptRoot\lib\backup.ps1" -Categories ($cats -join ',') }
            Pause-Key
        }
        default { }
    }
}

function Menu-Settings {
    while ($true) {
        $cfg = Get-ZenConfig
        Show-Header
        Write-Host "`nAutomatic backup settings:"
        Write-Host " 1) Frequency        (now: $($cfg.schedule.frequency))"
        Write-Host " 2) How many to keep (now: $($cfg.keep))"
        Write-Host " 3) Categories       (now: $($cfg.categories -join ','))"
        Write-Host " 4) Backups folder   (now: $($cfg.backupFolder))"
        Write-Host " 0) Back"
        switch (Read-Host "`nChoice") {
            '1' {
                Write-Host "`n a) Daily"
                Write-Host " b) Every N hours"
                Write-Host " c) Weekly"
                Write-Host " d) At logon"
                Write-Host " e) Disabled (no automatic backup)"
                switch ((Read-Host 'Choice').Trim().ToLower()) {
                    'a' { $cfg.schedule.frequency = 'daily';   $cfg.schedule.time = Read-ZenTime -Default $cfg.schedule.time }
                    'b' { $cfg.schedule.frequency = 'hourly';  $cfg.schedule.everyHours = Read-ZenInt -Prompt 'Every how many hours' -Min 1 -Max 24 -Default $cfg.schedule.everyHours }
                    'c' { $cfg.schedule.frequency = 'weekly';  $cfg.schedule.weekday = Read-ZenWeekday -Default $cfg.schedule.weekday; $cfg.schedule.time = Read-ZenTime -Default $cfg.schedule.time }
                    'd' { $cfg.schedule.frequency = 'onlogon' }
                    'e' { $cfg.schedule.frequency = 'disabled' }
                }
                Save-ZenConfig $cfg
                Write-Host (Set-ZenSchedule $cfg) -ForegroundColor Green
                Pause-Key
            }
            '2' {
                $cfg.keep = Read-ZenInt -Prompt 'Keep how many backups before deleting the oldest' -Min 1 -Max 999 -Default $cfg.keep
                Save-ZenConfig $cfg; Write-Host 'Saved.' -ForegroundColor Green
                Pause-Key
            }
            '3' {
                $picked = Pick-Categories @($cfg.categories)
                # These end up in every unattended backup, so ask once here
                # instead of on each silent run.
                if (@(Show-ZenSensitiveWarning $picked).Count) {
                    Write-Host "  Every automatic backup will contain them." -ForegroundColor Yellow
                    $ok = Read-Host "`nSave anyway? (y/n)"
                    if ($ok.Trim().ToLower() -ne 'y') { Write-Host 'Not saved.'; Pause-Key; continue }
                }
                $cfg.categories = $picked
                Save-ZenConfig $cfg
                Write-Host "Saved: $($cfg.categories -join ', ')" -ForegroundColor Green
                Pause-Key
            }
            '4' {
                $f = Read-Host 'New backups folder (you can use %USERPROFILE%)'
                if ($f) { $cfg.backupFolder = $f; Save-ZenConfig $cfg; Write-Host 'Saved.' -ForegroundColor Green }
                Pause-Key
            }
            default { return }
        }
    }
}

while ($true) {
    Show-Header
    Write-Host "`n 1) Backup now"
    Write-Host " 2) Restore from a backup"
    Write-Host " 3) Automatic backup settings"
    Write-Host " 4) Reset Zen to factory settings"
    Write-Host " 5) Open backups folder"
    Write-Host " 0) Quit"
    switch (Read-Host "`nChoice") {
        '1' { Menu-BackupNow }
        '2' { & "$PSScriptRoot\lib\restore.ps1"; Pause-Key }
        '3' { Menu-Settings }
        '4' { & "$PSScriptRoot\lib\reset.ps1"; Pause-Key }
        '5' { Start-Process explorer.exe (Get-BackupFolder (Get-ZenConfig)) }
        '0' { return }
        default { }
    }
}
