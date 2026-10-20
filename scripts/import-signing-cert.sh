#!/usr/bin/env bash
# Imports the release signing certificate into a temporary keychain (release CI only).
# Needs DROPKEEPER_SIGNING_P12 (base64 of the .p12) and DROPKEEPER_SIGNING_P12_PASSWORD; writes CODESIGN_IDENTITY,
# CODESIGN_KEYCHAIN and CODESIGN_CERT_SHA1 to $GITHUB_ENV for scripts/build-release.sh. See RELEASING.md.
set -euo pipefail
: "${DROPKEEPER_SIGNING_P12:?DROPKEEPER_SIGNING_P12 is not set — see RELEASING.md}"
: "${DROPKEEPER_SIGNING_P12_PASSWORD:?DROPKEEPER_SIGNING_P12_PASSWORD is not set — see RELEASING.md}"
: "${RUNNER_TEMP:?}" "${GITHUB_ENV:?}"
IDENTITY="DropKeeper Release (direcat)"
# SHA-1 of the certificate; the release fails if the app is signed with anything else.
CERT_SHA1=${DROPKEEPER_SIGNING_CERT_SHA1:-8d2bb959bc89da9dedea88c234b88f9ea92b5d16}
KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
P12="$RUNNER_TEMP/signing.p12"
trap 'rm -f "$P12"' EXIT
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
printf '%s' "$DROPKEEPER_SIGNING_P12" | base64 --decode > "$P12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$DROPKEEPER_SIGNING_P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
# codesign looks identities up in the user's keychain search list, so add the temporary keychain to it.
read -r -a SEARCH_LIST <<< "$(security list-keychains -d user | tr -d '"' | tr '\n' ' ')"
security list-keychains -d user -s "$KEYCHAIN" "${SEARCH_LIST[@]}"
# The self-signed certificate is not trusted, so check for it by hash rather than with -v.
security find-identity -p codesigning "$KEYCHAIN" | grep -qi "$CERT_SHA1" \
  || { echo "import-signing-cert: the imported certificate is not $CERT_SHA1" >&2; exit 1; }
{
  echo "CODESIGN_IDENTITY=$(printf '%s' "$CERT_SHA1" | tr '[:lower:]' '[:upper:]')"
  echo "CODESIGN_KEYCHAIN=$KEYCHAIN"
  echo "CODESIGN_CERT_SHA1=$CERT_SHA1"
} >> "$GITHUB_ENV"
echo "import-signing-cert: $IDENTITY ready in $KEYCHAIN"
