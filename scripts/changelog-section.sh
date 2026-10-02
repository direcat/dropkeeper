#!/usr/bin/env bash
# Prints the CHANGELOG section for one version (without its heading).
# Usage: scripts/changelog-section.sh <version> [CHANGELOG.md]
set -euo pipefail
VERSION="${1:?usage: changelog-section.sh <version> [file]}"
FILE="${2:-$(dirname "$0")/../CHANGELOG.md}"
SECTION=$(awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" { found = 1; next }
  found && /^## \[/ { exit }
  found { print }
' "$FILE" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
[ -n "$SECTION" ] || { echo "changelog-section: no section for $VERSION in $FILE" >&2; exit 1; }
printf '%s\n' "$SECTION"
