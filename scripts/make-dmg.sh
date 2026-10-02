#!/usr/bin/env bash
# Builds the drag-to-Applications DMG from build/release/DropKeeper.app.
# Usage: scripts/make-dmg.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: make-dmg.sh <version>}"
APP=build/release/DropKeeper.app
[ -d "$APP" ] || { echo "make-dmg: run scripts/build-release.sh first" >&2; exit 1; }

STAGE=build/release/dmg-stage
DMG="build/release/DropKeeper-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/DropKeeper.app"
tiffutil -cathidpicheck assets/dmg/dmg-background.png assets/dmg/dmg-background@2x.png \
  -out build/release/dmg-background.tiff

# CREATE_DMG_EXTRA can pass e.g. --skip-jenkins on hosts without a Finder session.
# shellcheck disable=SC2086
create-dmg \
  --volname "DropKeeper $VERSION" \
  --background build/release/dmg-background.tiff \
  --window-size 660 400 \
  --icon-size 96 \
  --icon "DropKeeper.app" 165 200 \
  --hide-extension "DropKeeper.app" \
  --app-drop-link 495 200 \
  ${CREATE_DMG_EXTRA:-} \
  "$DMG" "$STAGE"
rm -rf "$STAGE"
hdiutil verify "$DMG"
echo "make-dmg: $DMG"
