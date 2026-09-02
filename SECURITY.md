# Security policy

## Supported versions

Security fixes target the current `main` branch and the newest published release.
Older releases do not receive separate backports. Until a release is published,
use a current source build and review the known limitations in the README.

## Report a vulnerability privately

Use GitHub's **Report a vulnerability** action on the repository's Security tab:
https://github.com/dyd4dsh7/UpKeep/security/advisories/new

Do not open a public issue containing an exploit, credential, private diagnostic
log, or information about an affected third party. If private reporting is not
available, open an issue asking for a private contact route without disclosure
details. There is no bug bounty or guaranteed response time.

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

Official distribution builds must pass Developer ID signing, notarization,
stapling, and Gatekeeper validation. Debug builds and forks use different trust
identities. Keep official signing credentials in the protected `release` GitHub
environment; never expose them to pull-request jobs.
