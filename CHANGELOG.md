# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-08-01

### Added

- **Reset Zen to factory settings** (menu option 4, formerly "Wipe Zen for a fresh install").
  The safety backup is now offered instead of imposed, and skipping it lists exactly what
  would be lost. After the reset you can open Zen for a fresh start, or let the tool open
  Zen, wait for the new profile, wait for you to close it, and run a restore by itself.
- `zenbackup.log` in the backups folder, capped at 200 lines: the unattended scheduled task
  finally leaves a trace when it fails.
- Version number shown in the menu header.

### Changed

- `passwords` and `cookies` are marked as sensitive and are **no longer part of the default
  categories**. Existing `config.json` files are left untouched.
- Schedule prompts validate their input: `HH:mm` and `MON`..`SUN` re-prompt on a typo instead
  of crashing when the scheduled task is created.
- `Test-ZenRunning` matches Zen by executable path, so an unrelated process named `zen` no
  longer blocks a backup or a restore.
- Menu header rules are derived from a single width, so they line up.

### Fixed

- A corrupted or unreadable `config.json` was silently ignored: the tool ran on the built-in
  defaults while the user believed their own settings were in use. It now warns loudly.
- A restore of a zip without a valid `manifest.json` crashed with a raw exception. It now
  reports that the file was not produced by this tool and stops.
- The temporary extraction folder used during a restore survived every early exit, leaving a
  full copy of the profile, credentials included, in `%TEMP%`. It is now always removed.
- Backup failures are caught, logged, and reported with a non-zero exit code.

### Security

- Backups are plain zips: `passwords` and `cookies` are flagged `(!)` in every picker, warned
  about before each interactive backup, highlighted in the header when part of the automatic
  schedule, and documented in the new Security section of the README.

## [1.0] - 2026-06-25

First tagged version: menu-driven backup and restore of a Zen Browser profile, nine
categories, selective restore with profile repair, scheduled backups with retention.

[1.1.0]: https://github.com/Rumi-sketches/Zen-Auto-Backup-Tool/releases/tag/v1.1.0
[1.0]: https://github.com/Rumi-sketches/Zen-Auto-Backup-Tool/releases/tag/v1.0
