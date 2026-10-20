# Changelog

All notable changes to DropKeeper are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- The file name in the new-download prompt and in the list opens the file in its default app (the folder if the file is gone); the list menu also has Open, and Show prompt for a waiting file.
- The prompt, the list and the "Moved to Trash" notice show the same file icon as Finder.

### Changed
- Larger text in the prompt, notice, list, Settings and onboarding.
- Bigger timeout slider: larger dots, a halo around the selected one and thicker track lines.
- Clearer prompt buttons: "Keep" instead of "Keep it", and the main button says what it does ("Delete in 1 h" or "Keep") instead of "Done".
- Settings: "Default action" (was "If you don't choose") now comes before "Apply default action after" (was "Apply default after").
- Settings: "Watch folders" (was "Folders"); "Behavior" is split into "Timeline" (times numbered #1, #2… instead of Stop 1, Stop 2…) and "Expiry".
- Settings: remove buttons use a trash icon with a tooltip instead of a minus.
- Settings shows the build number next to the version, e.g. "Version 0.1.0 (68)".
- Settings and onboarding say "nothing leaves your computer".

### Fixed
- The prompt no longer jumps sideways when the pointer enters it in menu bar mode (it stays under the icon it opened at, so a click on the file name lands on it).

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
