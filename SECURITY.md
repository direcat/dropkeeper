# Security Policy

## Supported versions

Only the latest release receives security fixes. Update with `brew upgrade --cask dropkeeper` or download the newest build from [Releases](https://github.com/direcat/dropkeeper/releases/latest).

| Version        | Supported          |
| -------------- | ------------------ |
| Latest release | :white_check_mark: |
| Older releases | :x:                |

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Report them privately through [GitHub private vulnerability reporting](https://github.com/direcat/dropkeeper/security/advisories/new) instead.

Include what you can:

- the DropKeeper version and macOS version,
- steps to reproduce or a proof of concept,
- the impact you expect (for example which files could be deleted or read).

DropKeeper is maintained in spare time, so responses are best effort. You can expect an acknowledgement within a week. Confirmed issues are fixed in a new release and disclosed in a GitHub security advisory and the changelog, with credit unless you prefer to stay anonymous. If a report is declined, you will get an explanation.

## Scope

DropKeeper never uses the network and only acts on files in folders you choose to watch. Issues of particular interest:

- deleting or moving a file the user did not schedule (for example through symlinks, renames or replaced files),
- acting on files outside the watched folders,
- any code path that sends data over the network,
- tampering with release builds or the Homebrew cask.

Release builds are signed with a self-signed certificate and are not notarized by Apple; that by itself is a known limitation, not a vulnerability.
