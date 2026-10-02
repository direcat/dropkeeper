#!/usr/bin/env bash
# Renders the Homebrew cask for a release.
# Usage: scripts/render-cask.sh <version> <sha256>
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: render-cask.sh <version> <sha256>}"
SHA="${2:?usage: render-cask.sh <version> <sha256>}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "render-cask: invalid version '$VERSION'" >&2; exit 1; }
[[ "$SHA" =~ ^[0-9a-f]{64}$ ]] || { echo "render-cask: invalid sha256 '$SHA'" >&2; exit 1; }
sed -e "s/{{VERSION}}/$VERSION/" -e "s/{{SHA256}}/$SHA/" packaging/homebrew/dropkeeper.rb.template
