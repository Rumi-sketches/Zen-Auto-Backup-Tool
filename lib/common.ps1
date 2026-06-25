# common.ps1
# Shared configuration and helper functions for the Zen Backup Tool.
# Every script loads this file:  . "$PSScriptRoot\common.ps1"

$ErrorActionPreference = 'Stop'

# Repository root (this file lives in lib\)
$Global:ZenToolRoot = Split-Path $PSScriptRoot -Parent
$Global:ConfigPath  = Join-Path $ZenToolRoot 'config.json'
$Global:ZenRoot     = Join-Path $env:APPDATA 'zen'
$Global:TaskName    = 'ZenBackup'

# Map of categories to the profile files they cover.
# Entries ending with '\' are folders (copied recursively).
$Global:ZenCategories = [ordered]@{
    'appearance'  = @{ desc = 'UI, CSS, mods, themes, toolbar and icon layout'
                       items = @('chrome\', 'zen-themes.json', 'zen-themes\', 'zen-mods\', 'xulstore.json') }
    'shortcuts'   = @{ desc = 'Keyboard shortcuts'
                       items = @('zen-keyboard-shortcuts.json') }
    'spaces'      = @{ desc = 'Workspaces: names, themes, tabs, essentials, containers, tab notes'
                       items = @('zen-sessions.jsonlz4', 'zen-sessions-backup\', 'containers.json', 'zen-live-folders.jsonlz4', 'tabnotes.sqlite') }
    'preferences' = @{ desc = 'prefs.js (paths and SVG icon fix applied on restore)'
                       items = @('prefs.js') }
    'history'     = @{ desc = 'History and bookmarks'
                       items = @('places.sqlite', 'favicons.sqlite') }
    'passwords'   = @{ desc = 'Saved passwords'
                       items = @('key4.db', 'logins.json', 'logins-backup.json') }
    'cookies'     = @{ desc = 'Cookies and site permissions'
                       items = @('cookies.sqlite', 'permissions.sqlite') }
    'sessions'    = @{ desc = 'Open tabs and windows'
                       items = @('sessionstore.jsonlz4', 'sessionstore-backups\') }
    'extensions'  = @{ desc = 'Installed extensions'
                       items = @('extensions\', 'extensions.json', 'addonStartup.json.lz4') }
}

# Default settings used when config.json is missing or unreadable.
function New-DefaultConfig {
    [pscustomobject]@{
        backupFolder    = '%USERPROFILE%\ZenBackups'
        keep            = 10
        categories      = @($ZenCategories.Keys)
        schedule        = [pscustomobject]@{
            frequency  = 'daily'   # daily | hourly | weekly | onlogon | disabled
            time       = '13:00'
            everyHours = 6
            weekday    = 'SUN'
        }
        profileOverride = ''
    }
}

function Get-ZenConfig {
    if (Test-Path $ConfigPath) {
        try { return (Get-Content $ConfigPath -Raw | ConvertFrom-Json) } catch { }
    }
    return (New-DefaultConfig)
}

function Save-ZenConfig {
    param($Config)
    $Config | ConvertTo-Json -Depth 6 | Set-Content $ConfigPath -Encoding UTF8
}

function Get-BackupFolder {
    param($Config)
    [System.Environment]::ExpandEnvironmentVariables($Config.backupFolder)
}

function Test-ZenRunning {
    [bool](Get-Process -Name 'zen' -ErrorAction SilentlyContinue)
}

# All profiles, newest first (by prefs.js write time).
function Get-ZenProfiles {
    $dir = Join-Path $ZenRoot 'Profiles'
    if (-not (Test-Path $dir)) { return @() }
    Get-ChildItem $dir -Directory | ForEach-Object {
        $prefs = Join-Path $_.FullName 'prefs.js'
        [pscustomobject]@{
            Name     = $_.Name
            Path     = $_.FullName
            Modified = if (Test-Path $prefs) { (Get-Item $prefs).LastWriteTime } else { $_.LastWriteTime }
        }
    } | Sort-Object Modified -Descending
}

# Active profile: config override if set and present, otherwise the most
# recently used one. The folder prefix changes on reinstall, so auto-detect
# is the safe default.
function Resolve-ZenProfile {
    param($Config)
    if ($Config.profileOverride) {
        $p = Join-Path (Join-Path $ZenRoot 'Profiles') $Config.profileOverride
        if (Test-Path $p) { return $p }
    }
    $first = Get-ZenProfiles | Select-Object -First 1
    if ($first) { return $first.Path }
    return $null
}

# Copy a list of profile-relative items from $Src to $Dst.
function Copy-ZenItems {
    param([string]$Src, [string]$Dst, [string[]]$Items)
    $copied = 0; $skipped = 0
    foreach ($it in $Items) {
        $rel  = $it.TrimEnd('\')
        $from = Join-Path $Src $rel
        $to   = Join-Path $Dst $rel
        if (-not (Test-Path $from)) { $skipped++; continue }
        $parent = Split-Path $to -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        try {
            if ((Get-Item $from).PSIsContainer) {
                if (Test-Path $to) { Remove-Item $to -Recurse -Force -ErrorAction SilentlyContinue }
                Copy-Item $from $to -Recurse -Force -ErrorAction Stop
            } else {
                Copy-Item $from $to -Force -ErrorAction Stop
                # For SQLite databases, drop any stale -wal/-shm at the target so
                # they are not merged on top of the file we just restored.
                if ($to -match '\.sqlite$') {
                    foreach ($ext in '-wal', '-shm') {
                        $side = "$to$ext"
                        if (Test-Path $side) { Remove-Item $side -Force -ErrorAction SilentlyContinue }
                    }
                }
            }
            $copied++
        } catch {
            Write-Warning "  Could not copy '$rel': $($_.Exception.Message)"
            $skipped++
        }
    }
    [pscustomobject]@{ Copied = $copied; Skipped = $skipped }
}

# After restoring preferences: rewrite the old profile path to the new one,
# make sure the SVG icon fix is present, and remove user.js.
function Repair-ZenProfile {
    param([string]$TargetProfile, [string]$OldProfilePath)

    $prefs = Join-Path $TargetProfile 'prefs.js'
    if (Test-Path $prefs) {
        $content = Get-Content $prefs -Raw
        if ($OldProfilePath -and $OldProfilePath -ne $TargetProfile) {
            $content = $content.Replace(($OldProfilePath -replace '\\', '\\'), ($TargetProfile -replace '\\', '\\'))
            $content = $content.Replace($OldProfilePath, $TargetProfile)
        }
        if ($content -match 'svg\.context-properties\.content\.enabled') {
            $content = $content -replace 'user_pref\("svg\.context-properties\.content\.enabled",\s*false\);', 'user_pref("svg.context-properties.content.enabled", true);'
        } else {
            $content = $content.TrimEnd() + "`r`nuser_pref(`"svg.context-properties.content.enabled`", true);`r`n"
        }
        Set-Content $prefs -Value $content -Encoding UTF8
        Write-Host "  prefs.js fixed (paths and SVG icons)." -ForegroundColor DarkGray
    }
    $userjs = Join-Path $TargetProfile 'user.js'
    if (Test-Path $userjs) {
        Remove-Item $userjs -Force
        Write-Host "  Removed user.js (so preference changes can be saved)." -ForegroundColor DarkGray
    }
}

# Register or remove the Windows scheduled task from the config schedule.
# Uses schtasks through cmd /c so the quoting around the script path is
# predictable even when the path contains spaces.
function Set-ZenSchedule {
    param($Config)
    $backup = Join-Path $ZenToolRoot 'lib\backup.ps1'
    $inner  = '-NoProfile -ExecutionPolicy Bypass -File \"' + $backup + '\" -Quiet'
    $run    = '"powershell.exe ' + $inner + '"'
    $freq   = $Config.schedule.frequency

    cmd /c "schtasks /Delete /TN $TaskName /F" 2>$null | Out-Null
    switch ($freq) {
        'disabled' { return 'Automatic backup disabled.' }
        'daily'    { cmd /c "schtasks /Create /TN $TaskName /TR $run /SC DAILY /ST $($Config.schedule.time) /F"  | Out-Null }
        'hourly'   { cmd /c "schtasks /Create /TN $TaskName /TR $run /SC HOURLY /MO $($Config.schedule.everyHours) /F" | Out-Null }
        'weekly'   { cmd /c "schtasks /Create /TN $TaskName /TR $run /SC WEEKLY /D $($Config.schedule.weekday) /ST $($Config.schedule.time) /F" | Out-Null }
        'onlogon'  { cmd /c "schtasks /Create /TN $TaskName /TR $run /SC ONLOGON /F" | Out-Null }
        default    { return "Unknown frequency '$freq', task not created." }
    }
    return "Scheduled task '$TaskName' updated ($freq)."
}
