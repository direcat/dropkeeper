#!/usr/bin/env bash
# Builds the arm64 Release app and a zip for distribution.
# Usage: scripts/build-release.sh <version> [build-number]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: build-release.sh <version> [build-number]}"
BUILD="${2:-1}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "build-release: invalid version '$VERSION'" >&2; exit 1; }
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "build-release: invalid build number '$BUILD'" >&2; exit 1; }

OUT=build/release
DERIVED=build/release-dd
rm -rf "$OUT" "$DERIVED"
mkdir -p "$OUT"

xcodegen generate
xcodebuild build -project DropKeeper.xcodeproj -scheme DropKeeper -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" -quiet

APP="$DERIVED/Build/Products/Release/DropKeeper.app"
codesign --force --deep --sign - "$APP"
codesign --verify --strict --verbose=1 "$APP"

ARCHS=$(lipo -archs "$APP/Contents/MacOS/DropKeeper")
[ "$ARCHS" = "arm64" ] || { echo "build-release: expected arm64 only, got '$ARCHS'" >&2; exit 1; }
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
[ "$PLIST_VERSION" = "$VERSION" ] || { echo "build-release: Info.plist has '$PLIST_VERSION', expected '$VERSION'" >&2; exit 1; }

ditto "$APP" "$OUT/DropKeeper.app"
ditto -c -k --sequesterRsrc --keepParent "$OUT/DropKeeper.app" "$OUT/DropKeeper-$VERSION.zip"
shasum -a 256 "$OUT/DropKeeper-$VERSION.zip" | awk '{print $1}' > "$OUT/DropKeeper-$VERSION.zip.sha256"
echo "build-release: $OUT/DropKeeper-$VERSION.zip ($(cat "$OUT/DropKeeper-$VERSION.zip.sha256"))"
