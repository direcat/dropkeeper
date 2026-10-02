# Changelog

All notable changes to DropKeeper are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - YYYY-MM-DD

### Added
- Expiry for every new download in watched folders: 30 min, 1 h, 1 day, 10 days or keep (stops configurable).
- Prompt under the menu bar icon, optionally from the notch (Automatic follows the pointer).
- Menu bar icon with scheduled count, last-10-seconds countdown and a list with Keep, Change time, Show in Finder, Retry.
- "Moved to Trash" notice with Undo; optional permanent delete with confirmation.
- Tracks renames and moves inside watched folders; files moved out are kept; files present before install are never touched.
- Survives sleep, relaunch and a lost database (expiry stored on the file).
- Optional "Temporary" Finder tag, ignored extensions, quiet mode, grace period with a default choice, history retention.
- Several watched folders, launch at login, English and Czech.
- 100 % offline: no networking code, enforced in CI.
