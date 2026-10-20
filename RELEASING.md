# Releasing DropKeeper

## One-time setup (maintainer)

1. Create the public repository `direcat/homebrew-tap` with an empty `Casks/` folder (a README is enough).
2. Create a deploy key for the tap (it never expires and can only write to the tap):
   `ssh-keygen -t ed25519 -N "" -f tap_deploy`, then `gh repo deploy-key add tap_deploy.pub -R direcat/homebrew-tap --allow-write --title "dropkeeper release"`.
3. Store the private key as the Actions secret `HOMEBREW_TAP_DEPLOY_KEY`: `gh secret set HOMEBREW_TAP_DEPLOY_KEY -R direcat/dropkeeper < tap_deploy`. Keep a copy in your password manager, then delete both local files.
4. In `direcat/dropkeeper` → Settings → General → Social preview, upload `assets/social/dropkeeper-social-preview.png`.

## Every release

1. Go through [QA-CHECKLIST.md](QA-CHECKLIST.md) on real hardware.
2. In `CHANGELOG.md`, move the `Unreleased` entries into a new `## [x.y.z] - YYYY-MM-DD` section (the first release section already exists with the placeholder). Replace the `YYYY-MM-DD` placeholder with today's date.
3. Set `MARKETING_VERSION` in `project.yml` to `x.y.z` and commit: `chore: release x.y.z`.
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
