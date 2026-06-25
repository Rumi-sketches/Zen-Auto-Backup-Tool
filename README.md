# Zen Backup Tool

Made by [@Rumi-sketches](https://github.com/Rumi-sketches).

A small Windows tool that backs up and restores your [Zen Browser](https://zen-browser.app) setup: themes, mods, custom CSS, toolbar and icon layout, keyboard shortcuts, workspaces (Spaces), and optionally your history, passwords, cookies, sessions and extensions.

It runs from a simple menu. You pick what to back up, how often, and how many copies to keep. Everything is driven by one settings file (`config.json`), so you never have to touch the scripts.

## Download

**[Download the latest version (zip)](https://github.com/Rumi-sketches/Zen-Auto-Backup-Tool/archive/refs/heads/main.zip)**

Then:

1. Extract the zip anywhere you like (for example your Desktop).
2. Open the folder and double click `ZenBackup.bat`.

That is it. No installer. Tagged versions are also on the [Releases](https://github.com/Rumi-sketches/Zen-Auto-Backup-Tool/releases) page.

## Why this exists

Uninstalling Zen does not remove your profile, and reinstalling brings everything back. That is great until you actually want a clean start, reinstalling Windows or even changing PCs, but still keep your look and your Spaces. Unfortunately Zen and Firefox do not give you a full backup option, but this tool lets you save the parts you care about and put them back on a fresh profile, without copying files by hand and running into the usual problems (broken absolute paths in `prefs.js`, blank toolbar icons, a leftover `user.js` that stops your settings from saving).

## Requirements

- Windows 10 or 11
- Zen Browser installed at least once (so a profile exists)
- PowerShell 5.1, which ships with Windows

No installation, no dependencies. Just the files in this folder.

## Getting started

1. Download or clone this folder anywhere you like.
2. Double click `ZenBackup.bat`.
3. The menu opens. On the first run it creates `config.json` with sensible defaults.

From the menu you can:

- **Backup now**: full, or only the categories you choose.
- **Restore from a backup**: pick a backup, then pick which categories to bring back.
- **Automatic backup settings**: frequency, how many copies to keep, which categories, where to store them.
- **Wipe Zen for a fresh install**: takes a safety backup, then removes Zen's data folders.

If you prefer the command line, the same actions live in the `lib` folder:

```
powershell -File lib\backup.ps1            # backup using your saved settings
powershell -File lib\backup.ps1 -Categories appearance,spaces
powershell -File lib\restore.ps1           # interactive restore
powershell -File lib\wipe.ps1              # safety backup, then wipe
```

## Settings

All settings live in `config.json`. You can edit them from the menu or by hand.

| Setting | Meaning |
|---|---|
| `backupFolder` | Where the `.zip` backups are stored. Supports variables like `%USERPROFILE%`. |
| `keep` | How many backups to keep. Older ones are deleted automatically. |
| `categories` | What the automatic backup includes (see the table below). |
| `schedule.frequency` | `daily`, `hourly`, `weekly`, `onlogon`, or `disabled`. |
| `schedule.time` | Time of day for `daily` and `weekly`, as `HH:mm`. |
| `schedule.everyHours` | Interval for `hourly`. |
| `schedule.weekday` | Day for `weekly` (`MON` to `SUN`). |
| `profileOverride` | Folder name of a specific profile. Leave empty to auto detect the active one. |

The automatic backup is a Windows scheduled task named `ZenBackup`. The menu creates and updates it for you when you change the frequency.

## Categories

| Category | What it covers |
|---|---|
| `appearance` | UI, custom CSS, mods, themes, toolbar and icon layout |
| `shortcuts` | Keyboard shortcuts |
| `spaces` | Workspaces: names, themes, tabs, essentials, containers, tab notes |
| `preferences` | `prefs.js`, with path and SVG icon fixes applied on restore |
| `history` | History and bookmarks |
| `passwords` | Saved passwords |
| `cookies` | Cookies and site permissions |
| `sessions` | Open tabs and windows |
| `extensions` | Installed extensions |

## Restoring onto a fresh install

1. Reinstall Zen, open it once so it creates a profile, then close it completely.
   - If it detects an old configuration, create a backup first and use option 4, "Wipe Zen for a fresh install".
2. Run the tool and choose **Restore**.
3. Pick your backup, then pick the categories you want. For just your look and your Spaces, choose `appearance`, `shortcuts`, `spaces` and `preferences`.

Zen must be closed during a restore. The tool checks this and stops if Zen is still running.

## How Spaces are stored

This was trivial to understand. All of your workspace definitions (names, colors, order, tabs, essentials) live in a single file, `zen-sessions.jsonlz4`, under its `spaces` key. They are not in `places.sqlite`. The `spaces` category backs up that file, so restoring `spaces` is enough to get your workspaces back. You do not need `history`.

## What it can and cannot do

It can:

- Back up and restore your Zen look, shortcuts, workspaces, and data, all or in part.
- Run automatically on a schedule and keep a fixed number of copies.
- Restore onto a brand new profile, fixing the absolute paths in `prefs.js` and the blank toolbar icons that usually break a manual copy.
- Move your setup to another Windows machine by copying a backup `.zip` across.

It cannot:

- Sync in real time. It takes snapshots, it is not a live sync service.
- Guarantee a perfect copy of databases (history, cookies, passwords) while Zen is open. SQLite keeps recent changes in a side file, so for those categories close Zen first or run the backup at a time when it is closed. Workspace and appearance files are written atomically and are always safe.
- Work on macOS or Linux (I did not have a macOS or Linux device to test). The paths and the scheduler are Windows only. The backup format itself is just a zip of profile files, so the data is portable even if the scripts are not.
- Merge two profiles. A restore overwrites the selected files in the target profile.

## Notes

- Your profile folder name has a random prefix (for example `xygu6nr4.Default (release)`) that changes every time you reinstall Zen. The tool auto detects the active profile, so this is handled for you.
- Backups are plain zip files. You can open one and pull out a single file if you ever need to.
- This project is not affiliated with Zen Browser.

## Disclaimer

This is an open source project I built for my own needs and my own use. It comes with no warranty of any kind. I am not responsible if something goes wrong, if a backup or restore fails, or if your backups are lost. Always keep a separate copy of anything you cannot afford to lose, and test a restore before you rely on it.

## License

MIT. See [LICENSE](LICENSE).
