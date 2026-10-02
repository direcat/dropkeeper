# Contributing to DropKeeper

Thanks for helping. A few rules keep the project what it promises to be.

## Ground rules

- **No networking. Ever.** No `URLSession`, `Network.framework`, web views, analytics, crash reporters or update checks. `scripts/offline-guard.sh` and `scripts/check-binary.sh` enforce it; PRs that add network access will not be merged.
- **No new dependencies** without an issue discussing why (today the only one is GRDB).
- Apple Silicon and macOS 15+ only.
- Everything in the repository is in English. UI strings live in `App/Resources/Localizable.xcstrings`; add a Czech translation (or ask in the PR and we will help).

## Workflow

1. `brew install xcodegen swiftlint` and `xcodegen generate`.
2. Make your change with tests (Swift Testing). Core logic belongs in `Packages/DropKeeperCore` and must be testable without UI.
3. Before opening a PR run:

       swift test --package-path Packages/DropKeeperCore
       xcodebuild test -project DropKeeper.xcodeproj -scheme DropKeeper -destination 'platform=macOS,arch=arm64'
       swift format lint --strict --recursive App Packages/DropKeeperCore/Sources Packages/DropKeeperCore/Tests
       swiftlint lint --strict
       scripts/offline-guard.sh
       python3 scripts/check-localizations.py

4. For UI changes, go through the relevant parts of [QA-CHECKLIST.md](QA-CHECKLIST.md) using a safe test run (it explains the `-dbPath` / `-watch` arguments that keep your real data untouched).
5. Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages.

## AI-assisted contributions

DropKeeper itself is AI-coded, so AI-assisted PRs are welcome — you are still responsible for understanding and testing what you submit.
