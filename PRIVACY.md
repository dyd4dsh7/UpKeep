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
feeds, GitHub, Mozilla, Homebrew, language package registries, Ollama's registry,
and Hugging Face. Opening an external updater or a project page invokes that
service's own privacy policy. Package managers and model runtimes continue to
manage their own authentication and storage.

## What stays on the Mac

Preferences, source selections, exclusions, and repository mappings use macOS
UserDefaults. Diagnostics, update history, and app backups are stored under
`~/Library/Application Support/Upkeep/`. Diagnostics retain up to 2,000 entries;
backups retain up to three per app and twenty in total.

Diagnostics redact common credential patterns, URL queries, and the home-directory
prefix before storage/export. Redaction cannot guarantee that every sensitive
value is removed. Review exported logs before sharing them. Exports include app
and macOS versions and may include installed application names and source hosts.
Nothing automatically uploads diagnostic exports to the project.

## Permissions and changes

macOS may request App Management access, notification permission, or authentication
for an operation. Grant only what you want to use. Homebrew, developer tooling,
and local-model checks are optional. Updates, package adoption, restores, and
cleanup can modify your applications or development environment; review the
operation before confirming it. Backups do not cover every package manager or
replace a system backup.

Removing Upkeep does not automatically remove its preferences, logs, history, or
backups. Quit the app before removing its local data; deleting the backup directory
also removes Upkeep's ability to restore those versions.
