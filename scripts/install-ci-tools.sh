#!/usr/bin/env bash
# Installs pinned build tools into $RUNNER_TEMP/bin (CI) or build/tools/bin (local).
set -euo pipefail
XCODEGEN_VERSION=2.46.0
SWIFTLINT_VERSION=0.65.1
CREATE_DMG_VERSION=1.3.0
ROOT="${RUNNER_TEMP:-$(cd "$(dirname "$0")/.." && pwd)/build/tools}"
BIN="$ROOT/bin"
mkdir -p "$BIN" "$ROOT/src"
cd "$ROOT/src"

curl -fsSL -o xcodegen.zip "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
unzip -q -o xcodegen.zip -d xcodegen
ln -sf "$ROOT/src/xcodegen/xcodegen/bin/xcodegen" "$BIN/xcodegen"

curl -fsSL -o swiftlint.zip "https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"
unzip -q -o swiftlint.zip -d swiftlint
ln -sf "$ROOT/src/swiftlint/swiftlint" "$BIN/swiftlint"

curl -fsSL -o create-dmg.tar.gz "https://github.com/create-dmg/create-dmg/archive/refs/tags/v${CREATE_DMG_VERSION}.tar.gz"
tar -xzf create-dmg.tar.gz
# create-dmg locates support/ relative to its real path, so a symlink would break it.
printf '#!/usr/bin/env bash\nexec "%s/src/create-dmg-%s/create-dmg" "$@"\n' "$ROOT" "$CREATE_DMG_VERSION" > "$BIN/create-dmg"
chmod +x "$BIN/create-dmg"

if [ -n "${GITHUB_PATH:-}" ]; then echo "$BIN" >> "$GITHUB_PATH"; fi
"$BIN/xcodegen" --version
"$BIN/swiftlint" version
"$BIN/create-dmg" --version
