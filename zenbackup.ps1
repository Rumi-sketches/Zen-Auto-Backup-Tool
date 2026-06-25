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
    Write-Host "============ Zen Backup Tool  -  by @Rumi-sketches ============" -ForegroundColor Cyan
    Write-Host (" Profile : {0}" -f $(if ($prof) { Split-Path $prof -Leaf } else { 'not found' }))
    Write-Host (" Backups : {0}" -f (Get-BackupFolder $cfg))
    Write-Host (" Auto    : {0}   keep {1}   [{2}]" -f $sched, $cfg.keep, ($cfg.categories -join ','))
    Write-Host "========================================================" -ForegroundColor Cyan
}

function Pick-Categories {
    param([string[]]$Current)
    $keys = @($ZenCategories.Keys)
    Write-Host "`nCategories:`n"
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $mark = if ($Current -contains $keys[$i]) { '[x]' } else { '[ ]' }
        '{0,2}) {1} {2,-11} {3}' -f ($i + 1), $mark, $keys[$i], $ZenCategories[$keys[$i]].desc | Write-Host
    }
    Write-Host "`n  Enter = keep current   |   'all' = everything" -ForegroundColor DarkGray
    $sel = Read-Host 'Type the numbers you want (comma separated)'
    if ([string]::IsNullOrWhiteSpace($sel)) { return $Current }
    if ($sel.Trim().ToLower() -eq 'all') { return $keys }
    $picked = $sel -split ',' | ForEach-Object {
        $n = [int]($_.Trim()) - 1
        if ($n -ge 0 -and $n -lt $keys.Count) { $keys[$n] }
    }
    if (-not $picked) { return $Current }
    return @($picked)
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
                    'a' { $cfg.schedule.frequency = 'daily';   $cfg.schedule.time = (Read-Host 'Time HH:mm (e.g. 13:00)') }
                    'b' { $cfg.schedule.frequency = 'hourly';  $cfg.schedule.everyHours = [int](Read-Host 'Every how many hours') }
                    'c' { $cfg.schedule.frequency = 'weekly';  $cfg.schedule.weekday = (Read-Host 'Day MON/TUE/WED/THU/FRI/SAT/SUN').ToUpper(); $cfg.schedule.time = (Read-Host 'Time HH:mm') }
                    'd' { $cfg.schedule.frequency = 'onlogon' }
                    'e' { $cfg.schedule.frequency = 'disabled' }
                }
                Save-ZenConfig $cfg
                Write-Host (Set-ZenSchedule $cfg) -ForegroundColor Green
                Pause-Key
            }
            '2' {
                $n = Read-Host 'Keep how many backups before deleting the oldest'
                if ($n -match '^\d+$' -and [int]$n -ge 1) { $cfg.keep = [int]$n; Save-ZenConfig $cfg; Write-Host 'Saved.' -ForegroundColor Green }
                Pause-Key
            }
            '3' {
                $cfg.categories = Pick-Categories @($cfg.categories)
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
    Write-Host " 4) Wipe Zen for a fresh install"
    Write-Host " 5) Open backups folder"
    Write-Host " 0) Quit"
    switch (Read-Host "`nChoice") {
        '1' { Menu-BackupNow }
        '2' { & "$PSScriptRoot\lib\restore.ps1"; Pause-Key }
        '3' { Menu-Settings }
        '4' { & "$PSScriptRoot\lib\wipe.ps1"; Pause-Key }
        '5' { Start-Process explorer.exe (Get-BackupFolder (Get-ZenConfig)) }
        '0' { break }
        default { }
    }
}
