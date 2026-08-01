# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-01

First public release.

### Added

- Menu-driven tool (`ZenBackup.bat`) for backing up and restoring a Zen Browser profile.
- Nine backup categories: appearance, shortcuts, spaces, preferences, history,
  passwords, cookies, sessions, extensions.
- Selective restore with automatic repair of the restored profile: absolute paths in
  `prefs.js` rewritten, SVG icon fix applied, leftover `user.js` removed.
- Automatic backups through a Windows scheduled task: daily, every N hours, weekly,
  at logon, or disabled. Retention keeps the most recent N archives.
- **Reset Zen to factory settings**: optional safety backup, removal of Zen's data
  folders, then a choice between opening Zen fresh or going straight into a restore
  (opens Zen, waits for the new profile, waits for it to be closed, then restores).
- `zenbackup.log` in the backups folder, so failures of the unattended task are visible.
- Everything configurable from `config.json`.

### Security

- `passwords` and `cookies` are marked as sensitive, excluded from the default
  categories, flagged `(!)` in every picker and warned about before each backup:
  the archives are plain zips, and anyone who can read them can extract those files.

[1.0.0]: https://github.com/Rumi-sketches/Zen-Auto-Backup-Tool/releases/tag/v1.0.0
