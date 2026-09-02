# Upkeep

Upkeep is a native SwiftUI macOS application that scans installed apps and checks publisher and package-manager update sources. First-run setup starts with focused application management; Homebrew and the broader developer environment are explicit opt-ins.

The app includes a standard unified macOS toolbar with a prominent live update counter, a menu-bar status item, and a Dock icon badge using the same focused count. The primary count covers application updates, requested Homebrew packages, and macOS updates; global developer packages and Homebrew dependencies remain available in their dedicated workspaces without overwhelming the main queue. It also provides native Settings for every source and supported developer manager, configurable launch/background checks, beta visibility, and notifications.

Individual app, package, and local-model releases can be skipped without hiding later versions, or ignored until restored from Settings. Skipped and ignored updates are excluded from the update list, sidebar badge, menu-bar count, and notifications. Batch review groups recommended updates separately from manual actions, major releases, prereleases, dependencies, and developer-environment changes; only stable updates Upkeep can complete directly are selected by default.

## Update sources

- Mac App Store metadata for production App Store installations
- Sparkle appcast feeds declared by applications or their runtime preferences
- Homebrew casks, when Homebrew is installed
- GitHub Releases discovered from app and Electron update metadata, trusted bundle mappings, or a user-verified repository
- Ollama registry manifests and LM Studio model repositories for locally installed AI models

TestFlight, Setapp, Microsoft AutoUpdate, Steam, Adobe Creative Cloud, JetBrains Toolbox, Epic Games, Spotify, Discord, standalone Tailscale, and macOS-managed apps are identified separately and routed to their owning updater. Steam download progress is read from local manifests. Sparkle appcasts that declare a package installer open the app's built-in updater instead of presenting the package as a normal download action.

Apps with an embedded updater remain labeled as built-in-updater apps even when
their publisher configures the release feed at runtime. Advanced app details can
attach an `owner/project` GitHub repository; Upkeep validates that it has
published releases before saving the bundle-specific mapping. External update
actions remain pending until the installed bundle reports the expected version.

## Apple Silicon migration

On Apple Silicon Macs, Intel-only apps show a warning in application lists and details. **Move to Apple Silicon** opens a guide to the existing update manager, Homebrew cask, or developer releases. Installation is completed through that source; Upkeep does not assume that a native download exists or automatically replace the app. **Verify Installed App** rereads the original app location and confirms ARM support, including Universal builds and same-version replacements. Missing or unreadable executables remain unverified. Detection describes the main executable, not every embedded helper or the architecture of an already-running process.

## Homebrew workspace

Upkeep inventories installed formulae and casks, separates requested packages from dependencies, filters available updates, and exposes package details. Apps matched against Homebrew's official cask catalog can be adopted with Homebrew's native `--adopt` workflow.

## macOS and recovery

The macOS section reads Apple's Software Update catalog, lists compatible full installers, and opens Apple's authenticated settings for stable or beta-channel enrollment and installation. Before supported GUI app updates, Upkeep creates a local backup and adds a History entry that can restore the previous app bundle. It retains the three newest backups per app and twenty backups overall, removes a newly created backup when its update fails, and marks older history entries when their backup has expired. Formula and macOS recovery entries explain the supported Time Machine, versioned-formula, or macOS Recovery path when direct rollback is not available.

## Developer packages

Upkeep inventories globally installed npm, pnpm, Python/pip, RubyGems, and Cargo packages when their package managers are available. Manager filters only appear for installed tools, and packages without updates remain visible with a Current status. It preserves the discovered executable path—such as an NVM Node installation—when applying an update. Apps not currently managed by Homebrew also contribute to the update count when Homebrew's official cask catalog has a newer version; Upkeep backs up the app before replacing it and enrolling it under Homebrew management.

Package rows use bundled manager artwork and open detailed metadata when selected. npm, pnpm, pip, RubyGems, and Cargo packages can be installed at an explicit published version. Homebrew version selection follows its versioned-formula model; historical cask releases are only available when the cask itself exposes them.

Developer package details load available releases from the package manager or registry into a version menu and select the latest release by default. The Developer toolbar can refresh all installed managers or only npm, pnpm, Python, RubyGems, or Cargo.

The Homebrew and Developer toolbars also expose supported cleanup operations for Homebrew, npm, pnpm, and uv. Upkeep first performs a non-destructive check, shows Homebrew's dry-run estimate or clearly labels when a manager cannot predict its cleanup size, and asks for confirmation before cleaning. It then reports the disk space reclaimed.

## Local AI models

Upkeep detects locally installed Ollama and LM Studio models without showing empty runtime sections. Ollama models are checked by comparing their local and registry manifest digests. LM Studio model files are checked against their originating Hugging Face repository. Supported updates run through `ollama pull` or `lms get`, so credentials, storage, and model management remain with the installed runtime.

The model workspace uses bundled artwork downloaded from the official Ollama and LM Studio websites, with a native generic AI symbol when a logo is unavailable.

## Changelog

Upkeep includes its native changelog inside Settings. The complete release history is also maintained in [CHANGELOG.md](CHANGELOG.md).

Upkeep never downloads executables from its own servers. App Store updates open in the App Store, Sparkle downloads come from the app's declared developer feed, and Homebrew apps are upgraded through the local Homebrew installation.

## Build

Requires macOS 14 or newer and Apple Command Line Tools.

```sh
swift test
./scripts/package-app.sh debug
open outputs/Upkeep.zip
```

## Performance

For repeatable, offline performance measurements, run
`./scripts/benchmark-performance.sh outputs/performance/current.log`.
The benchmark uses an optimized build and isolated fixtures; it does not run
package managers or apply updates. See the [performance report](docs/performance/2026-08-31.md)
for baseline measurements, results, tradeoffs, and comparison commands.
The [second performance pass](docs/performance/2026-08-31-services.md) covers
diagnostics loading/redaction and developer release sorting. Run it with
`./scripts/benchmark-performance.sh outputs/performance/services.log services`.
The [third performance pass](docs/performance/2026-08-31-search.md) covers global
search across all seven result groups. Run it with
`./scripts/benchmark-performance.sh outputs/performance/search.log search`.

## Release

Direct distribution requires a Developer ID Application certificate and a
`notarytool` keychain profile. The release command signs with Hardened Runtime,
submits the archive to Apple's notary service, staples the ticket, and verifies
the result with `codesign`, `stapler`, and Gatekeeper before keeping the ZIP.

```sh
xcrun notarytool store-credentials upkeep-notary
export UPKEEP_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export UPKEEP_NOTARY_PROFILE="upkeep-notary"
./scripts/release.sh
```

Release packaging intentionally fails rather than producing an ad-hoc signed
artifact when either credential is missing.

The `Release` GitHub Actions workflow runs the same script for version tags and
manual dispatches. It expects repository secrets named
`DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `KEYCHAIN_PASSWORD`,
`APPLE_ID`, `APPLE_TEAM_ID`, `NOTARY_PASSWORD`, and
`UPKEEP_SIGNING_IDENTITY`.

The app bundle declares its canonical GitHub repository, so Upkeep discovers
its own published releases and routes users to the signed release artifact when
an Upkeep update is available.
