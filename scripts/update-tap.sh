#!/usr/bin/env bash
# Commits the rendered cask to the direcat/homebrew-tap tap (release CI only).
# Usage: HOMEBREW_TAP_DEPLOY_KEY=<ssh private key> scripts/update-tap.sh <version> <sha256>
# The key is a write-enabled deploy key of direcat/homebrew-tap (it does not expire; see RELEASING.md).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: update-tap.sh <version> <sha256>}"
SHA="${2:?usage: update-tap.sh <version> <sha256>}"
if [ -z "${HOMEBREW_TAP_DEPLOY_KEY:-}" ]; then
  echo "::warning::HOMEBREW_TAP_DEPLOY_KEY is not set — the Homebrew tap was NOT updated. See RELEASING.md."
  exit 0
fi
TAP_DIR=build/tap
SSH_DIR=$(mktemp -d)
trap 'rm -rf "$SSH_DIR"' EXIT
(umask 077 && printf '%s\n' "$HOMEBREW_TAP_DEPLOY_KEY" > "$SSH_DIR/key")
# GitHub's published host key (gh api meta), pinned so the push can't go anywhere else.
echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" > "$SSH_DIR/known_hosts"
export GIT_SSH_COMMAND="ssh -i $SSH_DIR/key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$SSH_DIR/known_hosts"
rm -rf "$TAP_DIR"
git clone --depth 1 git@github.com:direcat/homebrew-tap.git "$TAP_DIR"
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
