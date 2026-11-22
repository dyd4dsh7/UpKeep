<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/icon-dark.png">
  <img src="docs/images/icon-light.png" alt="Upkeep app icon" width="112">
</picture>

# Upkeep

**Keep your Mac's apps, packages, and developer tools up to date from one native app.**

[![Latest release](https://img.shields.io/github/v/release/dyd4dsh7/UpKeep?label=release)](https://github.com/dyd4dsh7/UpKeep/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-blue)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)

[Download](https://github.com/dyd4dsh7/UpKeep/releases/latest) ·
[Changelog](CHANGELOG.md) ·
[Privacy](PRIVACY.md) ·
[Report a bug](https://github.com/dyd4dsh7/UpKeep/issues)

<img src="docs/images/main-window.png" alt="Upkeep's Applications view listing installed apps with available updates, with TablePro's Sparkle update and release notes open in the detail pane" width="880">

</div>

## Why Upkeep

- **One list for everything.** Apps, Homebrew, macOS, packages from 24 developer
  tools (npm, pip, Cargo, Go, Docker, and more), and local AI models share one
  **All Updates** view, with a live count in the toolbar, menu bar, and Dock.
- **Uses what you already have.** Upkeep works through the tools installed on your
  Mac. Homebrew and developer checks are opt-in.
- **Updates from the real source.** App Store updates open in the App Store,
  Sparkle downloads come from the developer's own feed, and Homebrew upgrades run
  through your local Homebrew. Upkeep has no download servers of its own.
- **Safe by default.** App updates are backed up first and can be restored from
  History. Batch review only preselects stable updates Upkeep can finish itself.
- **Security checks built in.** The CVE Checker flags known advisories for
  installed apps and packages.

## Install

Requires **macOS 14 or newer** on **Apple Silicon**. Intel source builds are not
currently tested.

1. Download `Upkeep.zip` and `Upkeep.zip.sha256` from
   [GitHub Releases](https://github.com/dyd4dsh7/UpKeep/releases/latest). Only download builds from there.
2. In the download folder, run:
   ```sh
   shasum -a 256 -c Upkeep.zip.sha256
   ```
3. Extract the ZIP and move `Upkeep.app` to Applications.

> [!IMPORTANT]
> Current releases are signed locally and **not notarized** by Apple, so macOS
> blocks the first launch. After the checksum passes, Control-click `Upkeep.app`,
> choose **Open**, and confirm. You can also use **Open Anyway** in
> System Settings › Privacy & Security. Do not turn off Gatekeeper.
> Each release says whether its build is notarized.

From 0.25.5, Upkeep updates itself: **Upkeep › Check for Upkeep Updates…**
verifies the release's checksum and Ed25519 signature before installing in place.
If a release has no build attached, [build from source](#build-from-source).

## What Upkeep checks

| Source | How Upkeep checks |
| --- | --- |
| **Mac App Store** | App Store metadata for production installs |
| **Sparkle** | Appcast feeds declared by the app, its runtime preferences, or a trusted mapping |
| **Publisher version services** | Chrome, Edge, Firefox, Thunderbird, Brave, standalone JetBrains IDEs, Zoom, Slack, and 1Password |
| **Electron update servers** | The release manifest (such as `latest-mac.yml`) of apps that use electron-updater's generic provider |
| **Homebrew** | Installed formulae and casks, including dependencies |
| **GitHub Releases** | Repos found in app or Electron update metadata, trusted mappings, or a repo you verify |
| **macOS** | Apple's Software Update catalog and full installers |
| **Developer packages** | Global packages from 24 managers, including npm, pnpm, Yarn, Bun, pip, uv, RubyGems, Cargo, Go, and Docker images |
| **Local AI models** | Ollama registry manifests, LM Studio's Hugging Face repos, and the Hugging Face cache |

Apps with their own updater are recognised and handed to it: TestFlight, Setapp,
Microsoft AutoUpdate, Steam, Adobe Creative Cloud, JetBrains Toolbox, Epic Games,
Spotify, Discord, standalone Tailscale, and macOS-managed apps.

## Features

### Update review

Skip one release without hiding later ones, or ignore an update until you restore
it in Settings. Skipped and ignored updates are left out of every count and
notification. Batch review separates recommended updates from manual actions,
major releases, prereleases, dependencies, and developer-environment changes.

<details>
<summary>More about update sources</summary>

- A Homebrew cask that matches an installed app appears once, as the app update.
- Sparkle appcasts that declare a package installer open the app's built-in
  updater instead of downloading the package.
- Apps with an embedded updater stay labelled as such even when the publisher sets
  the feed at runtime. Some of these, such as ChatGPT, are checked through the
  feed packaged in the app.
- Publisher version services and Electron update servers only report the newest
  release; the app's built-in updater installs it. Electron prereleases are hidden
  from stable installs unless you include prereleases, and staged rollouts are
  shown once they reach everyone.
- JetBrains IDEs and Zoom are compared by build number, so patch releases with
  the same marketing version are found.
- In advanced app details you can attach an `owner/project` GitHub repo. Upkeep
  checks it has published releases before saving the mapping.
- External update actions stay pending until the installed app reports the
  expected version. Steam download progress is read from local manifests.
- Settings cover every source and developer manager, launch and background
  checks, beta visibility, and notifications.

</details>

### Backups and recovery

Before a supported app update, Upkeep backs up the app and adds a History entry
that can restore it. It keeps the 3 newest backups per app and 20 overall, and
deletes a new backup if its update fails. For formulae and macOS, History explains
the Time Machine, versioned-formula, or macOS Recovery route instead.

### Homebrew

Browse installed formulae and casks, with requested packages separated from
dependencies. Apps that match Homebrew's official cask catalog can be adopted with
Homebrew's `--adopt` workflow. Apps not managed by Homebrew also count as updates
when the catalog has a newer version; Upkeep backs the app up before handing it
to Homebrew.

### Developer packages

Upkeep lists global packages for the managers you have installed:

- **JavaScript:** Node.js, Bun, Deno, npm, pnpm, Yarn, Volta, and fnm
- **Python:** Python/pip, pipx, and uv
- **Ruby and Rust:** RubyGems, Rustup, and Cargo
- **Other tools:** Go, Composer, .NET tools, GitHub CLI, and editor extensions for
  VS Code, Cursor, VSCodium, and Windsurf (now Devin Desktop)
- **System managers:** MacPorts, Nix, mise, and asdf
- **Containers:** Docker images pulled from a public registry

It keeps the executable path it found (such as an NVM Node install) when
updating, and lets you pick a specific published version.

Editor extensions are checked against the gallery each editor installs from, read
from its `product.json`: the Visual Studio Marketplace for VS Code, Open VSX for
VSCodium, and Cursor's and Windsurf's own marketplaces. Their versions differ, so
Upkeep only offers versions the editor can install.

Docker images are compared by content digest and updated with `docker pull`.
Upkeep only lists an image when its registry recognises the local digest, so
local builds are never flagged or overwritten, even when they share a public
image's name. Unqualified names are checked only when they are on Docker's
official image list, so local project names are not sent to Docker Hub.
Upkeep uses HEAD requests, which do not count toward Docker Hub's pull limit.
It doesn't sign in to registries, so private images aren't listed, and a
stopped Docker daemon is skipped quietly.

**Cleanup** for Homebrew, npm, pnpm, and uv starts with a dry run, shows the
estimated size (or says when a manager can't predict it), asks before cleaning,
and reports the space reclaimed.

### CVE Checker

Open **CVE Checker** in the System sidebar and choose **Check CVEs**. Checks also
run after launch, scheduled, and manual refreshes while **Automatically check CVEs**
is on (the default). No API key is needed.

| Software | Advisory source |
| --- | --- |
| Developer packages | [OSV](https://osv.dev) |
| Homebrew core formulae | [Homebrew advisory feed](https://formulae.brew.sh/api/advisories.json) |
| Selected apps and official casks | [NVD](https://nvd.nist.gov/developers/vulnerabilities) |

Apps and updates with known advisories get a CVE badge that links to the results.
**Review Updates…** reviews every affected item that has an update available.

> [!NOTE]
> An empty result means the source returned no known advisories for that version,
> not that the software is safe. A badge does not claim the available update fixes
> the advisory.

<details>
<summary>Coverage and limits</summary>

- NVD mappings currently cover stable Chrome, Firefox, Thunderbird, Safari, VLC,
  and Visual Studio Code. NVD matches are *potential* CVEs; check the linked
  record for platform applicability.
- Homebrew's feed has limited coverage. Third-party taps, unusual version schemes,
  unknown identities, and prereleases are marked **not covered**.
- Cask results use Homebrew's receipt version, which can lag an app's own updater.
- Advisories show the highest available source severity (CVSS where supported) and
  any fixed releases listed for the package. Missing ratings show as **Unrated**;
  missing fix data does not mean no fix exists.
- Records sharing CVE/GHSA aliases are grouped as one issue.
- Unavailable, rate-limited, or partial sources produce an **incomplete** check.
  NVD requests are paced at least 6.1 seconds apart.
- Results are kept for the app session. A changed version, or a result older than
  24 hours, needs a new check.
- Checks never install updates, and do not scan project lockfiles, embedded
  libraries, unlisted transitive dependencies, or macOS itself.

</details>

### Apple Silicon migration

Intel-only apps are flagged on Apple Silicon Macs. **Move to Apple Silicon** points
you to the app's update manager, Homebrew cask, or developer releases; Upkeep does
not assume a native build exists or replace the app itself. **Verify Installed
App** then confirms ARM support, including Universal builds. Only the main
executable is checked, not every helper.

### Local AI models

Upkeep finds installed Ollama and LM Studio models and compares them with their
registry or Hugging Face source. Updates run through `ollama pull` or `lms get`,
so credentials and storage stay with your runtime.

Models in the Hugging Face cache (`~/.cache/huggingface/hub`, or `HF_HUB_CACHE`
and `HF_HOME`), such as MLX models, are compared with their repository's `main`
branch. Updates run `hf download` for the files already cached, so the Hugging
Face CLI must be installed. Models downloaded at a pinned revision are left
alone, and gated or private models can't be checked without signing in.

## Privacy and permissions

Update checks contact the publishers and registries for the sources you enable.
Preferences, diagnostics, history, and backups stay on your Mac, and Upkeep runs no
analytics service of its own. See [PRIVACY.md](PRIVACY.md) for exactly what is read, sent, and kept.

macOS may ask for App Management access, notifications, permission to control
Terminal (for Homebrew commands that need your password), or authentication for a
specific action. Review updates and cleanup before confirming them. App backups are
limited and do not replace a system backup.

## Limitations

- Some apps only update through their publisher's updater or the App Store.
- Unavailable, blocked, or rate-limited sources can leave a check incomplete.
- Package-manager changes can affect your development environment. Arbitrary
  downgrades and automatic system rollback are not supported.
- Homebrew historical versions follow its versioned-formula model; old cask
  releases are only available when the cask exposes them.
- macOS 14 is the deployment target, but tests and smoke checks run on macOS 27.
  Not every supported macOS version is tested end to end.

## Build from source

You need **Xcode 26.6+ (Swift 6.3+)** or matching Command Line Tools with the
**macOS 26 SDK or newer**. No Apple Developer account or signing secrets are needed.

```sh
git clone https://github.com/dyd4dsh7/UpKeep.git
cd UpKeep
swift test
./script/build_and_run.sh
```

<details>
<summary>Toolchain notes and benchmarks</summary>

The SDK is newer than the macOS 14 target because newer SwiftUI APIs sit behind
availability checks. Tests use the toolchain's bundled Swift Testing, so no extra
package, backend override, or linker paths are needed. `UpkeepState` selects
SwiftUI's native State property wrapper without the macOS 27 SDK's macro plugin.

For offline performance measurements, run
`./scripts/benchmark-performance.sh outputs/performance/current.log`. It uses an
optimized build and fixtures, and never runs package managers or applies updates.
Add `services` or `search` after the log path to benchmark diagnostics and release
sorting, or global search. The [live scan benchmark](docs/performance/2026-11-22-live-scan.md)
measures a real full scan and the effect of its caches.

</details>

## Contributing and security

- Setup, project layout, and PR guidance: [CONTRIBUTING.md](CONTRIBUTING.md)
- Bugs and proposals: [GitHub Issues](https://github.com/dyd4dsh7/UpKeep/issues)
- Vulnerabilities (report privately): [SECURITY.md](SECURITY.md)
- Maintainer releases: [release guide](docs/releasing.md)

## Licence

Upkeep's original code and artwork are [MIT licensed](LICENSE). Third-party logos
in `Sources/Upkeep/Resources/ThirdPartyLogos/` belong to their owners and are
**not** covered by the MIT licence. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
for each logo's source and terms. Third-party names and logos do not imply
endorsement.
