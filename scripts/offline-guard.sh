#!/usr/bin/env bash
# Fails if any networking API appears in the sources or an unexpected dependency is resolved.
set -euo pipefail
cd "$(dirname "$0")/.."

# Networking APIs, plus APIs that can fetch a URL or run a networking tool
# (Data/String(contentsOf:) accept remote URLs; Process/NSTask can run curl).
PATTERN='URLSession|URLRequest|NSURLConnection|import Network|NWConnection|NWBrowser|NWListener|CFNetwork|CFSocket|CFStream|(^|[^a-zA-Z_])socket\(|WKWebView|Data\(contentsOf:|String\(contentsOf:|Process\(|NSTask'
DIRS=()
# OFFLINE_GUARD_DIRS (space separated) overrides the scanned directories, for the guard's own fixture tests.
for d in ${OFFLINE_GUARD_DIRS:-Packages/DropKeeperCore/Sources Packages/DropKeeperCore/Tests App/Sources App/Tests}; do
  [ -d "$d" ] && DIRS+=("$d")
done
INCLUDES=(--include='*.swift' --include='*.m' --include='*.h')

if grep -rnE "$PATTERN" "${INCLUDES[@]}" "${DIRS[@]}"; then
  echo "offline-guard: networking API found (see above). DropKeeper must stay 100% offline." >&2
  exit 1
fi

# URL literals in code. Lines that are only a comment (doc links) are allowed. Allowed entries are quoted literals
# matched as fixed strings: all of them are stripped from each line and the rest is re-tested, so a second URL on
# the same line is still caught.
URLS=$(grep -rnE 'https?://' "${INCLUDES[@]}" "${DIRS[@]}" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|/\*|\*)' || true)
if [ -n "$URLS" ]; then
  URLS=$(printf '%s\n' "$URLS" | awk '
    FNR == NR { if ($0 !~ /^[[:space:]]*(#|$)/) allowed[++n] = "\"" $0 "\""; next }
    {
      line = $0
      for (k = 1; k <= n; k++) while ((i = index(line, allowed[k])) > 0) line = substr(line, 1, i - 1) substr(line, i + length(allowed[k]))
      if (line ~ /https?:\/\//) print $0
    }' scripts/offline-allowlist.txt -)
fi
if [ -n "$URLS" ]; then
  echo "$URLS" >&2
  echo "offline-guard: URL literal found in code (see above). DropKeeper must stay 100% offline." >&2
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
