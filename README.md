# DropKeeper

Downloads that clean up after themselves. Every new download gets an expiry — 30 minutes, an hour, a day, ten days, or keep it. When time is up, DropKeeper moves the file to the Trash.

- 100 % offline — no analytics, no tracking, no network access at all
- Free and open source (MIT)
- Apple Silicon, macOS 15 or later

## How it works

A new file lands in a watched folder, a small prompt opens (from the notch, or under the menu bar icon), and you pick when it should go: 30 minutes, an hour, a day, ten days — or keep it. When the time is up, DropKeeper moves the file to the Trash. Rename it or move it into a subfolder and it is still tracked; move it out of the watched folders and it is kept.

Work in progress.

## Credits and transparency

DropKeeper is a functional open-source clone of [TempCat](https://voprexlabs.com/tempcat/) by Voprex Labs, and fully inspired by it. In the age of AI agents, selling small (if useful) utilities for money no longer feels like a viable model, so this one is free and open.

DropKeeper is AI-coded. That is what makes it possible for it to exist at all, for free and as open source. If that is a problem for you, that is completely fine — you don't have to use it.

## Build from source

Requirements: Apple Silicon Mac, macOS 15+, Xcode 26 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

    brew install xcodegen
    xcodegen generate
    open DropKeeper.xcodeproj

Core engine tests: `swift test --package-path Packages/DropKeeperCore`
