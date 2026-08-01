# common.ps1
# Shared configuration and helper functions for the Zen Backup Tool.
# Every script loads this file:  . "$PSScriptRoot\common.ps1"

$ErrorActionPreference = 'Stop'

# Repository root (this file lives in lib\)
$Global:ZenToolRoot    = Split-Path $PSScriptRoot -Parent
$Global:ConfigPath     = Join-Path $ZenToolRoot 'config.json'
$Global:ZenRoot        = Join-Path $env:APPDATA 'zen'
$Global:TaskName       = 'ZenBackup'
$Global:ZenToolVersion = '1.0.0'

# Map of categories to the profile files they cover.
# Entries ending with '\' are folders (copied recursively).
# 'sensitive' marks credentials that end up readable inside the plain zip:
# those categories stay out of the defaults and are always warned about.
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
    'passwords'   = @{ desc = 'Saved passwords'; sensitive = $true
                       items = @('key4.db', 'logins.json', 'logins-backup.json') }
    'cookies'     = @{ desc = 'Cookies and site permissions'; sensitive = $true
                       items = @('cookies.sqlite', 'permissions.sqlite') }
    'sessions'    = @{ desc = 'Open tabs and windows'
                       items = @('sessionstore.jsonlz4', 'sessionstore-backups\') }
    'extensions'  = @{ desc = 'Installed extensions'
                       items = @('extensions\', 'extensions.json', 'addonStartup.json.lz4') }
}

function Test-ZenSensitive {
    param([string]$Category)
    return ($ZenCategories.Contains($Category) -and $ZenCategories[$Category].sensitive -eq $true)
}

# The sensitive categories inside a selection, in category order.
function Get-ZenSensitive {
    param([string[]]$Categories)
    return @($ZenCategories.Keys | Where-Object { $Categories -contains $_ -and (Test-ZenSensitive $_) })
}

# Spell out what including credentials in a plain zip actually means. Returns
# the sensitive categories found, so callers can decide whether to confirm.
function Show-ZenSensitiveWarning {
    param([string[]]$Categories)
    $hit = Get-ZenSensitive $Categories
    if (-not $hit.Count) { return $hit }

    Write-Host "`n  WARNING: this backup includes credentials." -ForegroundColor Yellow
    foreach ($c in $hit) {
        "    - {0,-11} {1}" -f $c, ($ZenCategories[$c].items -join ', ') | Write-Host -ForegroundColor Yellow
    }
    Write-Host "  The zip is NOT encrypted. Anyone who can read it can extract your saved" -ForegroundColor Yellow
    Write-Host "  passwords and log in as you on sites you are signed into." -ForegroundColor Yellow
    if ($Categories -contains 'sessions') {
        Write-Host "  'sessions' also carries the live logins of your open tabs." -ForegroundColor DarkYellow
    }
    Write-Host "  Keep the backups folder off shared drives, cloud sync and USB sticks." -ForegroundColor DarkGray
    return $hit
}

# Validated HH:mm, normalized to two digits. Re-prompts instead of letting a
# typo blow up New-ScheduledTaskTrigger.
function Read-ZenTime {
    param([string]$Prompt = 'Time HH:mm (e.g. 13:00)', [string]$Default)
    while ($true) {
        $v = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($v) -and $Default) { return $Default }
        if ($v -match '^\s*([01]?\d|2[0-3])\s*[:.]\s*([0-5]\d)\s*$') {
            return '{0:D2}:{1}' -f [int]$Matches[1], $Matches[2]
        }
        Write-Host '  Use a 24h time between 00:00 and 23:59, for example 13:00.' -ForegroundColor Yellow
    }
}

function Read-ZenWeekday {
    param([string]$Prompt = 'Day MON/TUE/WED/THU/FRI/SAT/SUN', [string]$Default)
    $days = @('MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN')
    while ($true) {
        $v = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($v) -and $Default) { return $Default }
        $u = $v.Trim().ToUpper()
        if ($days -contains $u) { return $u }
        $match = $days | Where-Object { $u -like "$_*" } | Select-Object -First 1
        if ($match) { return $match }
        Write-Host "  Use one of: $($days -join ', ')." -ForegroundColor Yellow
    }
}

# Parse a user selection over a list of options. Tolerant on purpose: the
# prompts are the only place a typo can kill the script, and $ErrorActionPreference
# is 'Stop', so nothing here may cast blindly.
# Accepts: numbers, ranges (2-5), names, 'all'/'*', separated by comma/space/semicolon.
# Returns @{ Items = @(...); Invalid = @(...) }; Items is empty when nothing matched.
function Select-ZenItems {
    param(
        [string]$Selection,
        [string[]]$Options
    )
    $items = New-Object System.Collections.Generic.List[string]
    $bad   = New-Object System.Collections.Generic.List[string]
    $add   = { param($v) if ($v -and -not $items.Contains($v)) { $items.Add($v) } }

    foreach ($tok in ($Selection -split '[,;\s]+')) {
        $t = $tok.Trim()
        if (-not $t) { continue }
        if ($t -eq 'all' -or $t -eq '*') { foreach ($o in $Options) { & $add $o }; continue }

        if ($t -match '^(\d+)\s*-\s*(\d+)$') {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            if ($a -gt $b) { $c = $a; $a = $b; $b = $c }
            $any = $false
            for ($i = $a; $i -le $b; $i++) {
                if ($i -ge 1 -and $i -le $Options.Count) { & $add $Options[$i - 1]; $any = $true }
            }
            if (-not $any) { $bad.Add($t) }
            continue
        }

        if ($t -match '^\d+$') {
            $i = [int]$t
            if ($i -ge 1 -and $i -le $Options.Count) { & $add $Options[$i - 1] } else { $bad.Add($t) }
            continue
        }

        $match = $Options | Where-Object { $_ -eq $t } | Select-Object -First 1
        if ($match) { & $add $match } else { $bad.Add($t) }
    }
    return @{ Items = @($items); Invalid = @($bad) }
}

# Prompt until the user gives a usable selection (or an empty line, which
# returns $Default). Never throws on bad input: it explains and asks again.
function Read-ZenSelection {
    param(
        [string]$Prompt,
        [string[]]$Options,
        [string[]]$Default = @()
    )
    while ($true) {
        $sel = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($sel)) { return @($Default) }
        $r = Select-ZenItems -Selection $sel -Options $Options
        if ($r.Invalid.Count) {
            Write-Host ("  Not valid: {0}  (use numbers 1-{1}, ranges like 2-4, names, or 'all')" -f ($r.Invalid -join ', '), $Options.Count) -ForegroundColor Yellow
        }
        if ($r.Items.Count) { return $r.Items }
        Write-Host '  Nothing selected, try again.' -ForegroundColor Yellow
    }
}

# Read a whole number in a range, re-prompting instead of crashing.
function Read-ZenInt {
    param([string]$Prompt, [int]$Min = 1, [int]$Max = [int]::MaxValue, $Default = $null)
    while ($true) {
        $v = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($v) -and $null -ne $Default) { return [int]$Default }
        $n = 0
        if ([int]::TryParse($v.Trim(), [ref]$n) -and $n -ge $Min -and $n -le $Max) { return $n }
        Write-Host "  Enter a number between $Min and $Max." -ForegroundColor Yellow
    }
}

# Default settings used when config.json is missing or unreadable.
# Sensitive categories are opt-in: an automatic backup must not start writing
# credentials to disk unless the user asked for it.
function New-DefaultConfig {
    [pscustomobject]@{
        backupFolder    = '%USERPROFILE%\ZenBackups'
        keep            = 10
        categories      = @($ZenCategories.Keys | Where-Object { -not (Test-ZenSensitive $_) })
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
        try {
            return (Get-Content $ConfigPath -Raw | ConvertFrom-Json)
        } catch {
            # Never fail silently here: the user would believe their schedule,
            # categories and backup folder are in use while they are not.
            Write-Warning "config.json could not be read: $($_.Exception.Message)"
            Write-Warning "Falling back to the built-in defaults. YOUR SETTINGS ARE NOT BEING APPLIED."
            Write-Warning "Fix or delete '$ConfigPath' to get rid of this warning."
            Write-ZenLog "config.json unreadable ($($_.Exception.Message)), using defaults" 'ERROR'
        }
    }
    return (New-DefaultConfig)
}

function Save-ZenConfig {
    param($Config)
    $Config | ConvertTo-Json -Depth 6 | Set-Content $ConfigPath -Encoding UTF8
}

function Get-BackupFolder {
    param($Config)
    $f = [System.Environment]::ExpandEnvironmentVariables($Config.backupFolder)
    $Global:ZenLogFolder = $f   # so Write-ZenLog lands next to the backups
    return $f
}

# Append one line to zenbackup.log in the backups folder, keeping only the
# most recent entries. The scheduled task runs with -Quiet and no window, so
# this file is the only place a failure can show up. Must never throw.
function Write-ZenLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [string]$Folder,
        [int]$KeepLines = 200
    )
    try {
        if (-not $Folder) { $Folder = $Global:ZenLogFolder }
        if (-not $Folder) { $Folder = [System.Environment]::ExpandEnvironmentVariables((New-DefaultConfig).backupFolder) }
        if (-not (Test-Path $Folder)) { New-Item -ItemType Directory -Path $Folder -Force | Out-Null }

        $log  = Join-Path $Folder 'zenbackup.log'
        $line = '{0} | {1,-5} | {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -Path $log -Value $line -Encoding UTF8

        $lines = @(Get-Content $log -ErrorAction SilentlyContinue)
        if ($lines.Count -gt $KeepLines) {
            Set-Content -Path $log -Value ($lines | Select-Object -Last $KeepLines) -Encoding UTF8
        }
    } catch { }
}

# True when Zen itself is running. Matches on the executable path so an
# unrelated process named 'zen' does not block a backup or a restore. When the
# path cannot be read (elevated process) or Zen is not found on disk, fall back
# to the name: a false positive only costs a prompt, a false negative would let
# us overwrite a profile Zen is still writing to.
function Get-ZenProcess {
    $procs = @(Get-Process -Name 'zen' -ErrorAction SilentlyContinue)
    if (-not $procs.Count) { return @() }

    $exe = Find-ZenExe
    if (-not $exe) { return $procs }

    $mine = @($procs | Where-Object {
        $path = $null
        try { $path = $_.Path } catch { }
        (-not $path) -or ($path -eq $exe)
    })
    return $mine
}

function Test-ZenRunning {
    return (@(Get-ZenProcess).Count -gt 0)
}

# Locate zen.exe. The installer can be per-user or per-machine, so try the
# usual folders, then the App Paths registry keys, then the Start Menu
# shortcut. Returns $null when Zen is not installed.
function Find-ZenExe {
    $roots = @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    $subs  = @('Programs\Zen Browser\zen.exe', 'Programs\zen\zen.exe', 'Zen Browser\zen.exe', 'zen\zen.exe')
    foreach ($r in $roots) {
        foreach ($s in $subs) {
            $c = Join-Path $r $s
            if (Test-Path $c) { return $c }
        }
    }

    foreach ($hive in 'HKLM:', 'HKCU:') {
        $key = "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\zen.exe"
        try {
            $p = (Get-ItemProperty $key -ErrorAction Stop).'(default)'
            if ($p -and (Test-Path $p)) { return $p }
        } catch { }
    }

    $menus = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
    )
    foreach ($m in $menus) {
        if (-not (Test-Path $m)) { continue }
        $lnk = Get-ChildItem $m -Recurse -Filter 'Zen*.lnk' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($lnk) {
            try {
                $target = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk.FullName).TargetPath
                if ($target -and (Test-Path $target)) { return $target }
            } catch { }
        }
    }
    return $null
}

# Countdown on a single line, so a short explanation stays on screen long
# enough to be read before the script moves on.
function Wait-ZenCountdown {
    param([int]$Seconds = 6, [string]$Message = 'Starting in')
    for ($s = $Seconds; $s -gt 0; $s--) {
        Write-Host ("`r  {0} {1}s..." -f $Message, $s) -NoNewline -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
    }
    Write-Host ("`r" + (' ' * 40) + "`r") -NoNewline
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
# Uses the ScheduledTasks PowerShell module so paths with spaces are handled
# correctly without cmd /c quoting issues.
function Set-ZenSchedule {
    param($Config)
    $backup = Join-Path $ZenToolRoot 'lib\backup.ps1'
    $freq   = $Config.schedule.frequency

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    if ($freq -eq 'disabled') { return 'Automatic backup disabled.' }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
                  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$backup`" -Quiet"

    $dayMap = @{ MON = 'Monday'; TUE = 'Tuesday'; WED = 'Wednesday'; THU = 'Thursday'
                 FRI = 'Friday'; SAT = 'Saturday'; SUN = 'Sunday' }

    $trigger = switch ($freq) {
        'daily'   { New-ScheduledTaskTrigger -Daily -At $Config.schedule.time }
        'hourly'  {
            $t = New-ScheduledTaskTrigger -Once -At (Get-Date).Date
            $t.Repetition.Interval = "PT$($Config.schedule.everyHours)H"
            $t
        }
        'weekly'  {
            $day = $dayMap[$Config.schedule.weekday]
            New-ScheduledTaskTrigger -Weekly -DaysOfWeek $day -At $Config.schedule.time
        }
        'onlogon' { New-ScheduledTaskTrigger -AtLogOn }
        default   { return "Unknown frequency '$freq', task not created." }
    }

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Force | Out-Null
    return "Scheduled task '$TaskName' updated ($freq)."
}
