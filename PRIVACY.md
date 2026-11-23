# Privacy and local data

Upkeep does not require an Upkeep account. The application has no Upkeep-operated
analytics or telemetry endpoint. Update checks still contact the selected
publishers, Apple services, package registries, and model hosts; this is not an
offline-only application.

## What it reads and sends

Upkeep reads installed app bundles and update metadata, running app state,
selected package-manager inventories, and local model metadata. Depending on the
sources you enable, checks send app identifiers, repository names, package names
and version queries, or model identifiers/digests to the relevant service.
Those services also receive normal connection metadata such as your IP address.

Examples include Apple App Store and Software Update services, developer Sparkle
feeds and Electron update servers, GitHub, Mozilla, Google's Chrome version
service (which receives only the platform and release channel), the Microsoft
Edge, JetBrains, Zoom, Slack, and 1Password release services (which receive only
a product code or platform), Microsoft AutoUpdate's public update manifests
(which receive an app ID and channel), Claude Code's release service, Homebrew,
language package registries (including pub.dev, the Krew plugin index on GitHub,
Flutter's release list, SDKMAN!'s version service, and the Google Cloud CLI
release channel), Apple's simulator runtime list, editor extension
galleries (the Visual Studio Marketplace, Open VSX, and Cursor's and Windsurf's
marketplaces, which receive extension IDs), Docker image registries (which
receive image names and digests, and only official names for unqualified
images), GitHub's copy of Docker's official image list, Ollama's registry, and
Hugging Face. Opening an external updater or a project page invokes that
service's own privacy policy. Package managers and model runtimes continue to
manage their own authentication and storage. Tools Upkeep runs to check for
updates contact their own services under your settings for that tool; for
example, `az extension list-available` reads Microsoft's extension index and
follows your Azure CLI telemetry setting.

To show what each item is, Upkeep looks up a one-line description for the apps,
packages, and models it lists. Package names go to their registry (for example
npm, PyPI, RubyGems, crates.io, pub.dev, Packagist, Anaconda, NuGet, Docker Hub,
the Visual Studio Marketplace, and GitHub for GitHub CLI extensions and Go tools),
model repository names go to Hugging Face, App Store bundle identifiers go to
Apple's App Store lookup, and Steam app IDs go to the Steam store. Descriptions are
cached in `~/Library/Caches/Upkeep/item-descriptions.json` for up to 30 days.

GitHub allows 60 API requests an hour without signing in. When the GitHub CLI
(`gh`) is installed and signed in, Upkeep reads its token with `gh auth token`
and sends it only to `api.github.com`, which raises the limit to 5,000 requests
an hour. The token is kept in memory, never written to disk or diagnostics, and
not sent to any other host, including after a redirect. Turn off **Use GitHub CLI
sign-in** in Settings › Sources to stop this.

CVE checks run after launch, scheduled, and manual inventory refreshes when
**Automatically check CVEs** is enabled in Settings (enabled by default). They
also run when you choose **Check CVEs**. Turning off automatic CVE checks leaves
manual checks available. Registry package names, ecosystems, and installed
versions go to `api.osv.dev`. Curated application product/vendor identities,
installed versions, and a macOS CPE target go to `services.nvd.nist.gov`. Homebrew
formula matching downloads the shared advisory index from `formulae.brew.sh`;
individual formula names are matched locally. Local paths, bundle identifiers,
and installation contexts are not sent. The index is downloaded to a temporary
file that is deleted once it is read, and is used only during a check;
displayed results remain in memory for the app session, shared by the CVE Checker
and list badges. Opening advisory links contacts OSV, NVD, or GitHub.

Upkeep checks for its own updates at most every six hours while it is open, and
whenever you choose **Check for Upkeep Updates…**. Each check asks
`api.github.com` for this project's published releases; it sends no app, package,
or personal data beyond normal connection metadata. An update is downloaded from
GitHub only when you choose to install it. Turn off **Check for Upkeep updates**
in Settings › General to stop the automatic checks; the menu item still works.

## What stays on the Mac

Preferences, source selections, exclusions, and repository mappings use macOS
UserDefaults. Diagnostics, update history, and app backups are stored under
`~/Library/Application Support/Upkeep/`. Diagnostics retain up to 2,000 entries;
backups retain up to three per app and twenty in total. Installing an Upkeep update
keeps the previous version in `Self Update Backup` in the same folder.

To make later checks faster, Upkeep caches some results in `~/Library/Caches/`:
developer package names and versions (up to 30 minutes), macOS update and installer
lists (up to six hours), Homebrew's public cask catalog, and publisher update
feeds and release details from Sparkle, Electron update servers, GitHub, Mozilla, and other publisher release services (up to 30 minutes). Downloaded Upkeep
updates are staged there until they are installed. macOS may clear these caches
at any time; Upkeep rebuilds them on the next check.

Diagnostics redact common credential patterns, URL queries, and the home-directory
prefix before storage/export. Redaction cannot guarantee that every sensitive
value is removed. Review exported logs before sharing them. Exports include app
and macOS versions and may include installed application names and source hosts.
Nothing automatically uploads diagnostic exports to the project.

## Automatic updates and links

**Automatic updates** in Settings › General is off by default. When turned on,
Upkeep installs the updates you allowed after each scheduled check, using the
same sources and backups as a manual update. `upkeep://` links only open views
or start a check; installing always needs a click in Upkeep.

## Permissions and changes

macOS may request App Management access, notification permission, permission to
control Terminal (used when a Homebrew command needs your password), or
authentication for an operation. Grant only what you want to use. Homebrew, developer tooling,
and local-model checks are optional. Updates, package adoption, restores, and
cleanup can modify your applications or development environment; review the
operation before confirming it. Backups do not cover every package manager or
replace a system backup.

Removing Upkeep does not automatically remove its preferences, logs, history,
backups, or caches. Quit the app before removing its local data; deleting the
backup directory also removes Upkeep's ability to restore those versions.
