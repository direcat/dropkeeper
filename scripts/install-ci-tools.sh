#!/usr/bin/env bash
# Installs pinned build tools into $RUNNER_TEMP/bin (CI) or build/tools/bin (local).
set -euo pipefail
XCODEGEN_VERSION=2.46.0
SWIFTLINT_VERSION=0.65.1
CREATE_DMG_VERSION=1.3.0
XCODEGEN_SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
SWIFTLINT_SHA256=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
CREATE_DMG_SHA256=c50d2bc97c3d6292642bac55f530d247eaf4bf65ee605f26b4caf339383e381c
ROOT="${RUNNER_TEMP:-$(cd "$(dirname "$0")/.." && pwd)/build/tools}"
BIN="$ROOT/bin"
mkdir -p "$BIN" "$ROOT/src"
cd "$ROOT/src"

verify() { echo "$2  $1" | shasum -a 256 -c - >/dev/null || { echo "SHA-256 mismatch for $1" >&2; exit 1; }; }

curl -fsSL -o xcodegen.zip "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
verify xcodegen.zip "$XCODEGEN_SHA256"
unzip -q -o xcodegen.zip -d xcodegen
# XcodeGen resolves its SettingPresets relative to its real path, so a symlink would lose them.
# Remove any old symlink first: writing through it would overwrite the real binary.
rm -f "$BIN/xcodegen"
printf '#!/usr/bin/env bash\nexec "%s/src/xcodegen/xcodegen/bin/xcodegen" "$@"\n' "$ROOT" > "$BIN/xcodegen"
chmod +x "$BIN/xcodegen"

curl -fsSL -o swiftlint.zip "https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"
verify swiftlint.zip "$SWIFTLINT_SHA256"
unzip -q -o swiftlint.zip -d swiftlint
ln -sf "$ROOT/src/swiftlint/swiftlint" "$BIN/swiftlint"

curl -fsSL -o create-dmg.tar.gz "https://github.com/create-dmg/create-dmg/archive/refs/tags/v${CREATE_DMG_VERSION}.tar.gz"
verify create-dmg.tar.gz "$CREATE_DMG_SHA256"
tar -xzf create-dmg.tar.gz
# create-dmg locates support/ relative to its real path, so a symlink would break it.
printf '#!/usr/bin/env bash\nexec "%s/src/create-dmg-%s/create-dmg" "$@"\n' "$ROOT" "$CREATE_DMG_VERSION" > "$BIN/create-dmg"
chmod +x "$BIN/create-dmg"

if [ -n "${GITHUB_PATH:-}" ]; then echo "$BIN" >> "$GITHUB_PATH"; fi
"$BIN/xcodegen" --version
"$BIN/swiftlint" version
"$BIN/create-dmg" --version
