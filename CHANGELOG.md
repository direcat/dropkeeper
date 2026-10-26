# Changelog

All notable changes to DropKeeper are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- With the default action set to Keep, the prompt now preselects Keep, so Return keeps the file (before, it scheduled 1 h).

## [1.0.2] - 2026-10-20

### Added
- A "Move to Trash" action in the file list (a "Delete Permanently…" one, with confirmation, in permanent-delete mode) that removes a file right away, following the Expired files setting; the Trash version shows the usual notice with Undo.

### Changed
- Releases are signed with the project's own (free, self-signed) certificate instead of an ad hoc signature, so macOS keeps the Downloads permission after updates. This update asks for it one last time.

## [1.0.1] - 2026-10-20

### Fixed
- The first click on the prompt's timeline now picks the time; before, it only focused the panel and a second click was needed.
- The "Moved to Trash" notice no longer flashes "0 files" while it fades out.

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
