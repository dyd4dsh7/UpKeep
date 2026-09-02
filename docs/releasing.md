# Maintainer release guide

Official releases come from `dyd4dsh7/UpKeep`. Source contributors and forks do not
need access to the maintainer's Apple credentials.

## One-time setup

1. Confirm ownership/licensing and complete `docs/open-source-readiness.md`.
2. Protect `main` with required `test-and-package` and `secret-scan` checks and a
   pull request. Restrict version-tag changes to maintainers.
3. Create a GitHub environment named `release`. Limit its deployment refs to
   `main` and `v*` tags. Add a maintainer reviewer where the GitHub plan supports
   environment review. A sole maintainer must be allowed to review their own run.
4. Add these secrets to that environment through GitHub Settings, not this repo
   or a chat message:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64-encoded export of the Developer ID Application certificate and private key |
| `DEVELOPER_ID_P12_PASSWORD` | Password used to protect that export |
| `KEYCHAIN_PASSWORD` | Strong random password for the runner's temporary keychain |
| `APPLE_ID` | Apple account used for notarization |
| `APPLE_TEAM_ID` | Apple Developer team identifier |
| `NOTARY_PASSWORD` | App-specific password for notarization |
| `UPKEEP_SIGNING_IDENTITY` | Developer ID Application certificate identity |

Signing needs an appropriate Apple Developer membership and valid certificate.
The workflow does not create or purchase these. Never put a real certificate,
password, or key in an issue, PR, workflow file, or repository artifact.

## Prepare a version

1. Update `Support/Info.plist` version and build number, the native changelog in
   `Sources/Upkeep/Views/ChangelogView.swift`, and `CHANGELOG.md` consistently.
2. Move the applicable Unreleased notes into the dated version entry.
3. Merge only after both required checks pass. Smoke-test the packaged app and
   review update/restore behaviour on temporary fixtures and a suitable test Mac.
4. Create and push an annotated `vMAJOR.MINOR.PATCH` tag on that verified commit.
   The Release workflow starts automatically. A rerun may also be dispatched from
   `main`, specifying the existing tag.

The workflow verifies the tag matches the bundle version and belongs to `main`,
tests before importing credentials, signs with Hardened Runtime, notarizes,
staples, and validates with codesign, stapler, and Gatekeeper. It then creates a
**draft** GitHub Release containing `Upkeep.zip` and `Upkeep.zip.sha256`. Existing
releases are never overwritten. This workflow builds for Apple Silicon; it does
not produce a Universal binary.

## Publish the draft

Download the draft's archive and checksum; verify the checksum, extract it, and
run `./scripts/validate-release.sh /path/to/Upkeep.app`. Launch that exact bundle,
check the displayed version and key workflows, and review the release notes.
Publish the draft only after those checks. Confirm the public release and its
assets are downloadable without authentication and that self-update discovery
finds the new version.

If signing, notarization, or validation fails, no draft is created. Temporary
certificate files/keychains are removed and the previous local packaged archive
is preserved. Do not substitute a debug archive for a failed release.

## Local signing

```sh
xcrun notarytool store-credentials upkeep-notary
export UPKEEP_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export UPKEEP_NOTARY_PROFILE="upkeep-notary"
./scripts/release.sh
```

For credentials and logs, use a local keychain and private audit storage. Treat a
successful local build, CI, signing, notarization, and publication as separate
checks.
