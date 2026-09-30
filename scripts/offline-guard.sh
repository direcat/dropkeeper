#!/usr/bin/env bash
# Fails if any networking API appears in the sources or an unexpected dependency is resolved.
set -euo pipefail
cd "$(dirname "$0")/.."

PATTERN='URLSession|URLRequest|NSURLConnection|import Network|NWConnection|NWBrowser|NWListener|CFNetwork|CFSocket|CFStream|[^a-zA-Z_]socket\(|WKWebView'
DIRS=()
for d in Packages/DropKeeperCore/Sources App; do [ -d "$d" ] && DIRS+=("$d"); done

if grep -rnE "$PATTERN" --include='*.swift' --include='*.m' --include='*.h' "${DIRS[@]}"; then
  echo "offline-guard: networking API found (see above). DropKeeper must stay 100% offline." >&2
  exit 1
fi

RESOLVED=Packages/DropKeeperCore/Package.resolved
if [ -f "$RESOLVED" ]; then
  EXTRA=$(grep -E '"identity"' "$RESOLVED" | grep -v '"grdb.swift"' || true)
  if [ -n "$EXTRA" ]; then
    echo "offline-guard: unexpected dependency in $RESOLVED:" >&2
    echo "$EXTRA" >&2
    exit 1
  fi
fi
echo "offline-guard: OK"
