# Maintainer release guide

Official releases come from `dyd4dsh7/UpKeep`. Source contributors and forks do not
need access to the maintainer's Apple credentials.

Releases are built, signed and notarized locally. The repository has no GitHub
Actions workflows, so nothing runs on GitHub when a tag is pushed.

## One-time setup

1. Confirm ownership and licensing, including `THIRD_PARTY_NOTICES.md` for bundled logos.
1. Create the self-update signing key once with
   `swift scripts/update-signing.swift generate ~/.config/upkeep/update-signing.key`
   and put the printed public key in `SelfUpdate.publicKey`. Back the private key
   up somewhere safe and never commit it. If it is lost, generate a new key; copies
   with the old public key then need one manual update.
2. Install the Developer ID Application certificate in your login keychain and
   store notarization credentials (see Local signing below). Never put a real
   certificate, password, or key in an issue, PR, or repository artifact.

## Prepare a version

1. Update `Support/Info.plist` version and build number, the native changelog in
   `Sources/Upkeep/Views/ChangelogView.swift`, and `CHANGELOG.md` consistently.
2. Move the applicable Unreleased notes into the dated version entry.
3. Run `swift test -Xswiftc -warnings-as-errors` on `main`. Smoke-test the packaged
   app and review update/restore behaviour on temporary fixtures and a test Mac.
4. Build the signed, notarized archive with `./scripts/release.sh` (below). It
   writes `outputs/Upkeep.zip`, `outputs/Upkeep.zip.sha256`, and debug symbols in
   `outputs/Upkeep.app.dSYM` (keep these for crash reports; do not ship them).
   Extract the archive to a temporary folder and run
   `./scripts/validate-release.sh /path/to/Upkeep.app` on the extracted bundle.
   Without Developer ID credentials, `./scripts/package-app.sh local-release`
   produces the same optimized, stripped build signed locally (not notarized);
   say so in the release notes.
   Packaging also writes `outputs/Upkeep.zip.sig` when the update signing key
   exists (override its path with `UPKEEP_UPDATE_SIGNING_KEY`).
5. Create and push an annotated `vMAJOR.MINOR.PATCH` tag on that verified commit.

## Publish

Create a draft GitHub Release for the tag with `Upkeep.zip`, `Upkeep.zip.sha256`,
and `Upkeep.zip.sig` (installed copies of Upkeep update in place only when all
three are attached) and notes from `python3 scripts/release-notes.py vMAJOR.MINOR.PATCH`. Download the
draft's archive, verify the checksum, extract it, launch that exact bundle, check
the displayed version and key workflows, then publish. Confirm the assets are
downloadable without authentication and that self-update discovery finds the new
version. Do not substitute a debug archive for a failed release.

## Local signing

```sh
xcrun notarytool store-credentials upkeep-notary
export UPKEEP_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export UPKEEP_NOTARY_PROFILE="upkeep-notary"
./scripts/release.sh
```

For credentials and logs, use a local keychain and private audit storage. Treat a
successful local build, signing, notarization, and publication as separate
checks.
