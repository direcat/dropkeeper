# Changelog

All notable changes to DropKeeper are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-20

### Added
- Expiry for every new download in watched folders: 30 min, 1 h, 1 day, 10 days or keep (times configurable).
- Prompt under the menu bar icon, optionally from the notch (Automatic follows the pointer), with a timeline to pick the time and buttons that say what they do ("Delete in 1 h", "Keep").
- Menu bar icon with scheduled count, last-10-seconds countdown and a list with Open, Keep, Change time, Show in Finder, Retry and, for a waiting file, Show prompt.
- Click a file name in the prompt or the list to open the file in its default app.
- Finder file icons and Quick Look thumbnails in the prompt, the list and the notice.
- "Moved to Trash" notice with Undo; optional permanent delete with confirmation.
- Tracks renames and moves inside watched folders; files moved out are kept; files present before install are never touched.
- Survives sleep, relaunch and a lost database (expiry stored on the file).
- Optional "Temporary" Finder tag, ignored extensions, quiet mode, a default action applied after a grace period, history retention.
- Several watched folders, launch at login, English, Czech, German, Spanish and French with a language picker in Settings (including the system privacy prompts).
- 100 % offline: no networking code, enforced in CI.
