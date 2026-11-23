import SwiftUI

struct ChangelogView: View {
    @UpkeepState private var searchText = ""
    @UpkeepState private var expandedVersions = Set(UpkeepRelease.all.prefix(1).map(\.id))

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let matches = UpkeepRelease.all.compactMap { release -> (release: UpkeepRelease, changes: [String])? in
            let changes = matchingChanges(release)
            return changes.isEmpty ? nil : (release, changes)
        }

        VStack(spacing: 0) {
            HStack {
                TextField("Search versions or release notes", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if !query.isEmpty {
                    Button("Clear Search") { searchText = "" }
                }
            }
            .padding(.horizontal, UpkeepLayout.pageInset)
            .padding(.vertical, 12)
            Divider()

            if matches.isEmpty {
                WorkspaceEmptyState("No matching releases", systemImage: "list.bullet.rectangle",
                    description: Text("Try a version number or a word from the release notes."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(matches, id: \.release.id) { match in
                            releaseCard(match.release, changes: match.changes)
                        }
                        Link("Earlier releases are in the full changelog on GitHub",
                             destination: UpkeepRelease.fullChangelogURL)
                            .font(.callout)
                            .padding(.top, 4)
                    }
                    .padding(UpkeepLayout.pageInset)
                }
            }
        }
    }

    private func matchingChanges(_ release: UpkeepRelease) -> [String] {
        if query.isEmpty || release.version.localizedCaseInsensitiveContains(query)
            || release.date.localizedCaseInsensitiveContains(query) {
            return release.changes
        }
        return release.changes.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func releaseCard(_ release: UpkeepRelease, changes: [String]) -> some View {
        Group {
            if query.isEmpty {
                DisclosureGroup(isExpanded: expansion(for: release.id)) {
                    changeList(changes)
                } label: {
                    releaseHeading(release)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    releaseHeading(release)
                    changeList(changes)
                }
            }
        }
        .padding(14)
        .upkeepSurface()
    }

    private func expansion(for version: String) -> Binding<Bool> {
        Binding(
            get: { expandedVersions.contains(version) },
            set: { expanded in
                if expanded { expandedVersions.insert(version) }
                else { expandedVersions.remove(version) }
            }
        )
    }

    private func releaseHeading(_ release: UpkeepRelease) -> some View {
        HStack(spacing: 9) {
            Text(release.version)
                .font(.headline.monospacedDigit())
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(release.date).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func changeList(_ changes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            ForEach(changes.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(changes[index]).font(.callout)
                }
            }
        }
        .padding(.top, 10)
    }
}

private struct UpkeepRelease: Identifiable {
    var id: String { version }
    let version: String
    let date: String
    let changes: [String]

    /// The app lists releases from 0.24.0; CHANGELOG.md keeps the full history.
    static let fullChangelogURL = URL(string: "https://github.com/\(SelfUpdate.repository)/blob/main/CHANGELOG.md")!

    static let all = [
        UpkeepRelease(version: "0.25.22", date: "23 November 2026", changes: [
            "Lets you uninstall every app except those macOS protects, including Upkeep itself.",
            "Adds Uninstall for local AI models and for nearly every developer package."
        ]),
        UpkeepRelease(version: "0.25.21", date: "23 November 2026", changes: [
            "Adds Uninstall for Homebrew formulae and casks."
        ]),
        UpkeepRelease(version: "0.25.20", date: "23 November 2026", changes: [
            "Adds Uninstall for every app, using Homebrew for cask apps and the Trash for the rest."
        ]),
        UpkeepRelease(version: "0.25.19", date: "23 November 2026", changes: [
            "Lines up versions in app and source lists, whether or not a row has an update."
        ]),
        UpkeepRelease(version: "0.25.18", date: "23 November 2026", changes: [
            "Gives Settings more room and splits package managers into those found on this Mac and those not found.",
            "Makes the diagnostics log easier to read, with entries grouped by day and warnings and errors highlighted.",
            "Redesigns the About page with Upkeep's update status and project links."
        ]),
        UpkeepRelease(version: "0.25.17", date: "23 November 2026", changes: [
            "Gives the details panel a clearer layout, with one large Update button and quieter secondary actions.",
            "Checks pyenv and rbenv versions, the Google Cloud CLI, Azure CLI extensions, and Xcode simulator runtimes.",
            "Offers npm only releases that support the Node.js beside it, and warns when MacPorts' ports list is old.",
            "Stops reporting a quit Docker Desktop as a failed check."
        ]),
        UpkeepRelease(version: "0.25.16", date: "23 November 2026", changes: [
            "Stops showing App Store updates the Mac App Store doesn't offer, such as the iPhone version of TestFlight.",
            "Stops offering Node.js alpha and release-candidate builds to stable installs.",
            "Checks gems for the Ruby you installed with rbenv or Homebrew instead of macOS's built-in Ruby."
        ]),
        UpkeepRelease(version: "0.25.15", date: "23 November 2026", changes: [
            "Refreshes Homebrew's catalog before checking your packages, so Homebrew updates are no longer stale. Set HOMEBREW_NO_AUTO_UPDATE to turn this off.",
            "Shows every Software Update product, including Command Line Tools for Xcode and Safari.",
            "Checks nvm itself against its latest release."
        ]),
        UpkeepRelease(version: "0.25.14", date: "23 November 2026", changes: [
            "Checks Microsoft Office and Teams for updates on the channel Microsoft AutoUpdate uses, and opens AutoUpdate to install them.",
            "Adds Claude Code installed with its native installer to developer packages.",
            "Removes invisible characters from app names, and shows Apple utilities and Claude Code's helper app as managed."
        ]),
        UpkeepRelease(version: "0.25.13", date: "23 November 2026", changes: [
            "Adds pixi, Krew, juliaup, opam, Dart, Poetry, Flutter, GHCup, swiftly, Conda, and SDKMAN! to developer packages.",
            "Keeps SDKMAN! candidates on their vendor, so a Temurin JDK is never offered a different distribution."
        ]),
        UpkeepRelease(version: "0.25.12", date: "23 November 2026", changes: [
            "Compares Homebrew casks that update themselves with the installed app, so an app behind its cask is reported and one that updated itself shows its real version.",
            "Links casks to apps by the app bundles they install, such as Docker Desktop and Docker.app."
        ]),
        UpkeepRelease(version: "0.25.11", date: "23 November 2026", changes: [
            "Lists iPhone and iPad apps installed from the App Store on Apple silicon and checks them for App Store updates."
        ]),
        UpkeepRelease(version: "0.25.10", date: "23 November 2026", changes: [
            "Lists extensions for VSCodium and Windsurf (now Devin Desktop) alongside VS Code and Cursor.",
            "Checks each editor's extensions against the gallery it installs from, so Cursor no longer shows Visual Studio Marketplace versions it cannot install."
        ]),
        UpkeepRelease(version: "0.25.9", date: "23 November 2026", changes: [
            "Adds Docker Images: images pulled from a public registry are checked by digest and updated with docker pull. Local builds are never listed.",
            "Shows models from the Hugging Face cache, such as MLX models, and updates them with hf download."
        ]),
        UpkeepRelease(version: "0.25.8", date: "23 November 2026", changes: [
            "Checks Microsoft Edge, standalone JetBrains IDEs, Zoom, Slack, and 1Password against their publishers' release services.",
            "Checks Electron apps that update from their developer's own server, and ChatGPT through its packaged Sparkle feed.",
            "Checks UTM, PureMac, BlitzTree, and Spotifast against their GitHub releases.",
            "Fixes Chrome and Brave showing No update source in app details while up to date."
        ]),
        UpkeepRelease(version: "0.25.7", date: "23 November 2026", changes: [
            "Shows release notes with their formatting: headings, lists, tables, quotes, and HTML from Sparkle and GitHub appear as text instead of raw markup.",
            "Adds Check for Upkeep updates in Settings › General to turn off automatic update checks.",
            "Explains why Upkeep asks to control Terminal when a Homebrew command needs your password.",
            "Fixes externally managed apps repeating the same explanation under Managed by.",
            "Lists releases from 0.24.0 here, with a link to the full changelog on GitHub.",
            "Removes unused code."
        ]),
        UpkeepRelease(version: "0.25.6", date: "22 November 2026", changes: [
            "Explains Upkeep's own update checks and on-disk caches in the privacy policy.",
            "Removes unused code, including an unused command that would have upgraded every Homebrew package at once."
        ]),
        UpkeepRelease(version: "0.25.5", date: "22 November 2026", changes: [
            "Checks for Upkeep updates and installs them in place: Upkeep verifies each release's checksum and signature, then quits, replaces itself (keeping a backup), and reopens.",
            "Adds Upkeep › Check for Upkeep Updates…, an update banner, and update status in Settings › About.",
            "Matches the app's colours to its icon.",
            "Halves the app's size (20 MB to 10 MB) and lowers memory use, with peak memory down from about 550 MB to 355 MB."
        ]),
        UpkeepRelease(version: "0.25.4", date: "22 November 2026", changes: [
            "Uses about 40% less memory after an update check by caching a small summary of the Homebrew cask catalog instead of the full 19 MB catalog.",
            "Makes repeat checks steadier by reusing the macOS update list for up to an hour during automatic checks; the macOS page still checks Apple directly."
        ]),
        UpkeepRelease(version: "0.25.3", date: "22 November 2026", changes: [
            "Makes update checks faster, including the first check after opening Upkeep, by reusing RubyGems, npm, and Python results for up to 30 minutes while installed packages are unchanged.",
            "Keeps these results and the macOS full-installer list across launches; installing, updating, or removing a package always forces a fresh check."
        ]),
        UpkeepRelease(version: "0.25.2", date: "22 November 2026", changes: [
            "Makes full update checks about 25% faster by running independent macOS and developer-tool checks together and checking VS Code extensions in one request.",
            "Reuses the full macOS installer list for up to 6 hours during automatic checks; the macOS page still refreshes it on request."
        ]),
        UpkeepRelease(version: "0.25.1", date: "22 November 2026", changes: [
            "Shows official logos for package managers, model runtimes, and update sources, including Homebrew, npm, Node.js, Python, Rust, Go, GitHub, VS Code, Ollama, LM Studio, and Sparkle, with dark-mode versions.",
            "Shows the installed App Store, TestFlight, Steam, Setapp, and Microsoft AutoUpdate icons on their source pages.",
            "Lists every third-party logo with its owner, source, and terms in the third-party notices."
        ]),
        UpkeepRelease(version: "0.25.0", date: "22 November 2026", changes: [
            "Finds updates that were hidden before, including post-release versions such as 9.9p1 and 1.1.1w, Homebrew letter suffixes, -stable tags, and cask versions with a commit hash.",
            "Skipping or ignoring an app now also hides its Homebrew cask update, and a skipped release stays skipped whichever source reports it.",
            "Treats Sparkle canary, insider, and other named channels as prereleases, and compares Sparkle builds the way Sparkle does, removing phantom updates and false install failures.",
            "Reopens apps Upkeep quit for an update when the update fails but the original app is intact, and keeps the newest backup within the storage budget.",
            "Keeps a single main window that the menu bar, Dock icon, and notifications reopen; the menu bar count and Dock badge stay current while the window is closed.",
            "Adds pending updates and Update All Recommended to the menu bar, an Open at login setting, ⌘F for search, and Stop After Current Update for batch updates.",
            "Batch review shows every group the Updates header counts, with per-group selection and the apps it will quit; sidebar badges count pending updates only.",
            "Shows a checking state instead of empty lists during scans, and says Not checked yet or No update source instead of Up to date when nothing was checked.",
            "Redesigns workspaces, Settings, and dialogs, with a compact Updates header that adapts to light mode and update lists aligned into columns.",
            "Keeps update rows on one aligned line when the details panel opens, shortening long names and badges instead of reflowing rows.",
            "Improves responsiveness during scans and in large lists, runs CVE checks concurrently, batches App Store lookups, and briefly caches Sparkle feeds.",
            "Prepares the project for open source, with tests and signed releases run locally."
        ]),
        UpkeepRelease(version: "0.24.0", date: "2 September 2026", changes: [
            "Flags Intel-only apps on Apple Silicon Macs and guides replacement through their existing update manager, Homebrew cask, or developer releases. Native availability is not assumed.",
            "Verifies Apple Silicon and Universal replacements locally, including same-version installs, while leaving missing, unreadable, or differently identified apps unverified.",
            "Adds focused first-run profiles and persistent Basic and Advanced views, keeping developer tools, dependencies, prereleases, and technical details opt-in.",
            "Adopts native Liquid Glass navigation, toolbar search, shared resizable inspectors, clearer rows and actions, updated app artwork, and a reliable Dock update counter.",
            "Simplifies Settings, application filters, and batch review; only stable updates Upkeep can complete directly are selected by default.",
            "Adds targeted app and package refreshes with progress and Last checked times, richer technical details, and source diagnostics.",
            "Adds check-first cleanup for Homebrew, npm, pnpm, and uv with confirmation, available estimates, and reclaimed disk-space reporting.",
            "Distinguishes unchecked, disabled, failed, partial, and completed scans, and explains incomplete publisher checks in app details.",
            "Preserves Sparkle build-only updates through detection, download validation, source selection, and exclusions.",
            "Prevents conflicting updates, adoption, cleanup, and restores; stages and validates restore backups before replacement and preserves recovery copies on failure.",
            "Keeps successful installations recoverable when history cannot be saved, refreshes model history, and handles Upkeep self-updates externally.",
            "Deduplicates Homebrew casks in update lists and batch review without hiding same-named formulae.",
            "Hardens publisher destinations, redirects, downloads, archive extraction, staged app validation, and privileged Homebrew terminal handoffs.",
            "Fixes developer-package and pnpm cleanup failures caused by unavailable or read-only working and temporary directories.",
            "Speeds up library lookups, global search, diagnostics, and release menus, with repeatable offline benchmarks and regression coverage.",
            "Separates hover from selection, respects Reduce Motion, and fixes Settings and inspector constraint failures, progress-size faults, and search-selection state faults.",
            "Keeps test and standalone review diagnostics out of the app's persistent log.",
            "Automatically reopens applications that Upkeep temporarily quits after successful single or batch updates.",
            "Adds trusted GitHub release discovery for Stats and UniGetUI plus validated, user-supplied repository mappings.",
            "Finds runtime-configured Sparkle feeds and identifies apps that own their updater without incorrectly calling them unsupported.",
            "Routes Steam, Adobe Creative Cloud, JetBrains Toolbox, Epic Games, Spotify, Discord, standalone Tailscale, and macOS-managed apps to their publisher-owned updater.",
            "Reads Steam queue and download progress from local manifests and verifies external updates against the installed app bundle.",
            "Displays release provenance and Sparkle signature declarations, and matches Homebrew casks by their declared app artifacts.",
            "Adds signed and notarized release packaging with CI, release, and validation workflows.",
            "Rejects unrelated GitHub release tags from multi-product repositories and preserves installed prerelease channels.",
            "Scans every NVM installation, editor extensions, Python tool environments, Rust toolchains, GitHub CLI extensions, Go tools, Composer, .NET, MacPorts, Nix, mise, asdf, Volta, and fnm only when they are detected.",
            "Finds Bun and Yarn global packages and keeps packages from separate Node installations distinct.",
            "Parallelizes source work, caches Homebrew catalog data, and coalesces registry requests, reducing repeated full scans from about 18 seconds to roughly 2–3 seconds in local benchmarks.",
            "Includes recognizable artwork and safe manual-update handoffs for every newly supported manager.",
            "Groups Node.js, Bun, Deno, Yarn, npm, and pnpm in one JavaScript workspace with runtime and global-tool update checks.",
            "Moves Developer manager filtering into a compact, single-level toolbar menu that lists every detected ecosystem."
        ])
    ]
}
