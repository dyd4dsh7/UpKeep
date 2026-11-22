# Maintainer release guide

Official releases come from `dyd4dsh7/UpKeep`. Source contributors and forks do not
need access to the maintainer's Apple credentials.

Releases are built, signed and notarized locally. The repository has no GitHub
Actions workflows, so nothing runs on GitHub when a tag is pushed.

## One-time setup

1. Confirm ownership/licensing and complete `docs/open-source-readiness.md`.
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
   writes `outputs/Upkeep.zip`; extract it to a temporary folder and run
   `./scripts/validate-release.sh /path/to/Upkeep.app` on the extracted bundle.
5. Create and push an annotated `vMAJOR.MINOR.PATCH` tag on that verified commit.

## Publish

Create a draft GitHub Release for the tag with `Upkeep.zip`, `Upkeep.zip.sha256`
and notes from `python3 scripts/release-notes.py vMAJOR.MINOR.PATCH`. Download the
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
