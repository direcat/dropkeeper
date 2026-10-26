#!/usr/bin/env bash
# Checks a built DropKeeper.app keeps the offline promise:
# no networking frameworks, no DEBUG-only switches, the release bundle id, only allow-listed URL strings.
# Usage: scripts/check-binary.sh <path/to/DropKeeper.app>
set -euo pipefail
APP="$(cd "$(dirname "${1:?usage: check-binary.sh <DropKeeper.app>}")" && pwd)/$(basename "$1")"
cd "$(dirname "$0")/.."
BIN="$APP/Contents/MacOS/DropKeeper"
[ -x "$BIN" ] || { echo "check-binary: no executable at $BIN" >&2; exit 1; }
FAIL=0

# Debug builds split the code into DropKeeper.debug.dylib next to a stub executable, so inspect
# every Mach-O file in Contents/MacOS. A Release build has just the executable.
BINS=()
for f in "$APP/Contents/MacOS"/*; do [ -f "$f" ] && BINS+=("$f"); done
all_strings() { for f in "${BINS[@]}"; do strings -a "$f"; done; }

LINKED=$(for f in "${BINS[@]}"; do otool -L "$f" | tail -n +2 | awk '{print $1}'; done)
if echo "$LINKED" | grep -E 'Network\.framework|CFNetwork\.framework|WebKit\.framework|libcurl' ; then
  echo "check-binary: networking library linked (see above)" >&2; FAIL=1
fi
if [ -d "$APP/Contents/Frameworks" ] && find "$APP/Contents/Frameworks" -mindepth 1 -maxdepth 1 | grep -Ei 'network|curl|alamofire|sentry|firebase|analytics'; then
  echo "check-binary: suspicious embedded framework (see above)" >&2; FAIL=1
fi

# The exact DEBUG-only identifiers from App/Sources/AppDelegate.swift: the launch-argument keys
# (dbPath, noLoginItem, watch) and the debug defaults suite name. The compiler may inline short
# literals so they never show up in `strings`; the suite name is the reliable marker.
if all_strings | grep -E '^(dbPath|noLoginItem|watch)$|^net\.direcat\.dropkeeper\.debug\.dbpath$'; then
  echo "check-binary: DEBUG-only launch switches present in this build (see above)" >&2; FAIL=1
fi

# The release must keep exactly this bundle id (Debug builds use ...debug), or macOS permissions and the cask break.
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)
if [ "$BUNDLE_ID" != "net.direcat.dropkeeper" ]; then
  echo "check-binary: CFBundleIdentifier is '$BUNDLE_ID', expected exactly 'net.direcat.dropkeeper' (is this a Debug build?)" >&2; FAIL=1
fi

ALLOW=$(grep -vE '^[[:space:]]*(#|$)' scripts/binary-url-allowlist.txt || true)
URLS=$(all_strings | grep -Eo 'https?://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+' | sort -u || true)
UNEXPECTED=$(comm -23 <(echo "$URLS" | sed '/^$/d') <(echo "$ALLOW" | sort -u) || true)
if [ -n "$UNEXPECTED" ]; then
  echo "$UNEXPECTED" >&2
  echo "check-binary: URL strings not in scripts/binary-url-allowlist.txt (see above)" >&2; FAIL=1
fi

[ "$FAIL" = 0 ] && echo "check-binary: OK ($APP)"
exit "$FAIL"
