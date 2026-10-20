# Releasing DropKeeper

## One-time setup (maintainer)

1. Create the public repository `direcat/homebrew-tap` with an empty `Casks/` folder (a README is enough).
2. Create a deploy key for the tap (it never expires and can only write to the tap):
   `ssh-keygen -t ed25519 -N "" -f tap_deploy`, then `gh repo deploy-key add tap_deploy.pub -R direcat/homebrew-tap --allow-write --title "dropkeeper release"`.
3. Store the private key as the Actions secret `HOMEBREW_TAP_DEPLOY_KEY`: `gh secret set HOMEBREW_TAP_DEPLOY_KEY -R direcat/dropkeeper < tap_deploy`. Keep a copy in your password manager, then delete both local files.
4. Signing certificate (free, self-signed). Releases are signed with it so the designated requirement (`identifier "net.direcat.dropkeeper" and certificate root = H"…"`) stays the same across versions and macOS keeps the Downloads permission after an update. It does not replace notarization.
   - Create it once: `openssl req -x509 -newkey rsa:3072 -sha256 -days 7300 -nodes -keyout key.pem -out cert.pem -subj "/CN=DropKeeper Release (direcat)/O=direcat" -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" -addext "basicConstraints=critical,CA:false"`, then (with OpenSSL 3, e.g. Homebrew `openssl`; the system LibreSSL has no `-legacy`) `openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem -name "DropKeeper Release (direcat)" -out dropkeeper-release.p12`.
   - Secrets: `base64 -i dropkeeper-release.p12 | gh secret set DROPKEEPER_SIGNING_P12 -R direcat/dropkeeper` and `gh secret set DROPKEEPER_SIGNING_P12_PASSWORD -R direcat/dropkeeper`.
   - Put its SHA-1 (`openssl x509 -in cert.pem -noout -fingerprint -sha1`, lower case without colons) into `CERT_SHA1` in `scripts/import-signing-cert.sh`.
   - Keep the `.p12` and its password in a password manager and delete the local files. A new certificate means every user is asked for folder access once more, so don't replace it lightly.
5. In `direcat/dropkeeper` → Settings → General → Social preview, upload `assets/social/dropkeeper-social-preview.png`.

## Every release

1. Go through [QA-CHECKLIST.md](QA-CHECKLIST.md) on real hardware.
2. In `CHANGELOG.md`, move the `Unreleased` entries into a new `## [x.y.z] - YYYY-MM-DD` section (the first release section already exists with the placeholder). Replace the `YYYY-MM-DD` placeholder with today's date.
3. Choose the version (patch for fixes, minor for features, major for breaking changes), set it as `MARKETING_VERSION` in `project.yml` and as `DropKeeperCoreInfo.version` (plus its check in `SmokeTests.swift`), and commit: `chore: release x.y.z`. Between releases `master` keeps the last released version.
4. Tag and push: `git tag vx.y.z && git push origin master vx.y.z`.
   - The first CI run after pushing is the real compile check against the CI Xcode (Xcode 26.6 on `macos-26`); local development uses a newer Xcode.
   - If the DMG step fails on the runner because Finder scripting is unavailable, set `CREATE_DMG_EXTRA: --skip-jenkins` on the DMG step (the DMG then loses its background layout).
5. The Release workflow tests, builds, checks the binary, publishes the zip and DMG to GitHub Releases and updates the cask in the tap. If the tap step only printed a warning, the deploy key secret is missing — fix it and run `scripts/render-cask.sh x.y.z <sha256>` by hand into the tap.
   - If the key is set but the tap clone or push fails, the GitHub release is already published: check the deploy key (write access, matching secret) and update the tap by hand with `scripts/render-cask.sh`.
6. Check `brew install --cask direcat/tap/dropkeeper` on a clean account:
   - the first launch opens without a Gatekeeper prompt;
   - after `brew uninstall --zap --cask dropkeeper`, System Settings → General → Login Items no longer lists DropKeeper and `~/Library/Application Support/DropKeeper` is gone (verified for 1.0.0: the cask removes the login item too).

## Local dry run

    scripts/install-ci-tools.sh
    PATH="$PWD/build/tools/bin:$PATH" scripts/build-release.sh 0.0.0 1
    scripts/check-binary.sh build/release/DropKeeper.app
    PATH="$PWD/build/tools/bin:$PATH" scripts/make-dmg.sh 0.0.0
