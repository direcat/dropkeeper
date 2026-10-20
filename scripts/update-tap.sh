#!/usr/bin/env bash
# Commits the rendered cask to the direcat/homebrew-tap tap (release CI only).
# Usage: HOMEBREW_TAP_TOKEN=... scripts/update-tap.sh <version> <sha256>
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: update-tap.sh <version> <sha256>}"
SHA="${2:?usage: update-tap.sh <version> <sha256>}"
if [ -z "${HOMEBREW_TAP_TOKEN:-}" ]; then
  echo "::warning::HOMEBREW_TAP_TOKEN is not set — the Homebrew tap was NOT updated. See RELEASING.md."
  exit 0
fi
TAP_DIR=build/tap
rm -rf "$TAP_DIR"
git clone --depth 1 "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/direcat/homebrew-tap.git" "$TAP_DIR"
mkdir -p "$TAP_DIR/Casks"
scripts/render-cask.sh "$VERSION" "$SHA" > "$TAP_DIR/Casks/dropkeeper.rb"
cd "$TAP_DIR"
git config user.name "DropKeeper release"
git config user.email "release@users.noreply.github.com"
git add Casks/dropkeeper.rb
if git diff --cached --quiet; then
  echo "update-tap: cask already at $VERSION"
  exit 0
fi
git commit -m "dropkeeper $VERSION"
git push origin HEAD
echo "update-tap: pushed dropkeeper $VERSION"
