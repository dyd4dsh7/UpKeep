# Security policy

## Supported versions

Security fixes target the current `main` branch and the newest published release.
Older releases do not receive separate backports; update to the newest release
(**Upkeep › Check for Upkeep Updates…**) to receive fixes.

## Report a vulnerability privately

Use GitHub's **Report a vulnerability** action on the repository's Security tab:
https://github.com/dyd4dsh7/UpKeep/security/advisories/new

Do not open a public issue containing an exploit, credential, private diagnostic
log, or information about an affected third party. If the form is unavailable,
open an issue asking for a private contact route, without any details. There is
no bug bounty or guaranteed response time.

Include the affected version/commit, macOS version, impact, and minimal
reproduction using a temporary app or fixture. Include whether the problem
requires a malicious publisher feed, archive, local file, or package environment.
Remove personal identifiers and secrets from attachments even when the app's
redaction has already run.

## Relevant boundaries

Upkeep can replace installed applications and invoke package managers. Publisher
URL validation, redirect checks, archive extraction limits, code-signing and
identity checks, backup/restore transactions, and shell argument handling are
security-sensitive. Scanning an update source must not itself install an update.

Upkeep also updates itself. Before replacing itself it checks the release
archive's SHA-256 checksum and Ed25519 signature against the public key built into
the app, then checks the new app's bundle identifier, version, architecture, and
code signature. The private update-signing key must never be committed, shared,
or attached to an issue or pull request; a leaked key would let someone else
publish updates that installed copies accept.

Releases are built and signed on the maintainer's Mac; the repository has no CI
and stores no signing secrets. Builds signed with a Developer ID are notarized,
stapled, and checked with Gatekeeper. Builds without one are signed locally and
say so in their release notes. Debug builds and forks use different signing
identities.
