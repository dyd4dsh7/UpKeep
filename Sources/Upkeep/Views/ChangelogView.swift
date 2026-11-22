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
            Text(release.isUnreleased ? "Unreleased" : release.version)
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
    var isUnreleased: Bool { version == "Next" }

    static let all = [
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
        ]),
        UpkeepRelease(version: "0.23.1", date: "22 July 2026", changes: [
            "Drops stale update candidates when an app has already been updated outside Upkeep.",
            "Prevents Homebrew from replacing TestFlight, Setapp, or Microsoft AutoUpdate-managed apps.",
            "Treats stable platform-qualified versions correctly while preserving genuine prerelease channels.",
            "Keeps scheduled-check timing across relaunches and reads Sparkle release notes delivered as CDATA.",
            "Bounds rollback backups, removes failed-update backups, protects corrupt history, and marks expired backups accurately.",
            "Corrects the managed-updater launch error and adds regression coverage for these reliability paths."
        ]),
        UpkeepRelease(version: "0.23.0", date: "22 July 2026", changes: [
            "Records scan timing, update-source requests, version decisions, Homebrew commands, and update outcomes.",
            "Adds an at-a-glance dashboard, structured entry cards, searchable severity and category filters, plus export and clear controls in Settings.",
            "Formats scan durations and status values for readability and scopes warning and error totals to the latest completed scan.",
            "Redacts credentials, authenticated URLs, URL queries, and the user's home-directory path before saving or exporting entries.",
            "Keeps a bounded local history and includes version, source, duration, and failure context for troubleshooting."
        ]),
        UpkeepRelease(version: "0.22.0", date: "22 July 2026", changes: [
            "Groups compact Sort, Filter, and Density controls with consistent spacing at the far-left edge of each list toolbar.",
            "Keeps batch update actions on the far right and moves search into the sidebar.",
            "Searches apps, packages, models, macOS, and history in one global results workspace.",
            "Sorts apps by Default, A–Z, Z–A, install date, recent updates, source, or version.",
            "Filters app lists by available updates or unmapped apps.",
            "Adds an Unmapped Homebrew filter for casks without a matching application bundle.",
            "Adds persisted Comfortable and Compact list densities in list controls and Settings.",
            "Routes update-source failures into the searchable Diagnostics workspace."
        ]),
        UpkeepRelease(version: "0.21.0", date: "22 July 2026", changes: [
            "Distinguishes TestFlight builds from production Mac App Store installations and opens the correct updater.",
            "Detects Setapp editions and Microsoft AutoUpdate registrations without misclassifying other Microsoft apps.",
            "Prevents externally managed editions from receiving incompatible source checks or Homebrew adoption actions.",
            "Recognizes Sparkle package installers and opens the app's built-in updater while retaining the developer download.",
            "Shows update-management badges, explanations, and manager shortcuts in app details.",
            "Adds TestFlight, Setapp, and Microsoft AutoUpdate categories with live counts to the sidebar.",
            "Adds source-aware empty states with refresh and clear-search actions to app categories.",
            "Unifies sidebar, page-header, empty-state, and update-action icons around destination-specific SF Symbols."
        ]),
        UpkeepRelease(version: "0.20.0", date: "22 July 2026", changes: [
            "Adds a unified review sheet for selecting app, Homebrew, developer-package, and AI-model updates.",
            "Runs selected updates one at a time, continues after failures, and shows a result for every action.",
            "Identifies external App Store, Sparkle, and GitHub handoffs while keeping macOS installation separate.",
            "Prevents the same Homebrew-backed app and cask from being selected twice."
        ]),
        UpkeepRelease(version: "0.19.0", date: "22 July 2026", changes: [
            "Adds one-to-six-day, one-week, and one-, three-, and six-month time frames for both Skip and Ignore actions.",
            "Keeps timed skips version-specific while timed ignores suppress every version until expiry.",
            "Automatically restores expired updates and shows temporary exclusion deadlines in Settings.",
            "Keeps application exclusions intact when apps move and migrates existing path-based exclusions."
        ]),
        UpkeepRelease(version: "0.18.0", date: "22 July 2026", changes: [
            "Adds precise daily update checks with a user-selected time and visible next-check date.",
            "Replaces periodic polling with an efficient scheduler that responds immediately to preference changes.",
            "Adds a persistent option to hide the available-update count from the Dock icon."
        ]),
        UpkeepRelease(version: "0.17.0", date: "22 July 2026", changes: [
            "Retains every App Store, Homebrew, Sparkle, and GitHub source that reports an available update.",
            "Uses a deterministic preferred-source policy while keeping alternate versions and actions available in app details.",
            "Preserves last-known candidates for individual sources when a later scan partially fails."
        ]),
        UpkeepRelease(version: "0.16.0", date: "21 July 2026", changes: [
            "Adds opt-in prerelease updates for apps, packages, and macOS, with a warning before enabling unstable releases.",
            "Labels Alpha, Beta, RC, Preview, Nightly, Dev, and other prereleases throughout update and inventory lists.",
            "Keeps installed prereleases identifiable while hiding other prerelease and platform-specific package versions when the setting is off.",
            "Improves GitHub and Sparkle channel detection and makes semantic, calendar, and package-version ordering deterministic.",
            "Fixes npm and pnpm discovery and commands when Upkeep launches outside a terminal, including NVM and pnpm paths."
        ]),
        UpkeepRelease(version: "0.15.0", date: "21 July 2026", changes: [
            "Keeps the Updates workspace selected when opening package or model details.",
            "Keeps the chosen Homebrew, developer-package, or AI-model update row highlighted.",
            "Shows the complete package or model detail view beside the Updates list."
        ]),
        UpkeepRelease(version: "0.14.9", date: "21 July 2026", changes: [
            "Removes the raw source URL bar from app details.",
            "Rebuilds app actions as a responsive grid of large capsule buttons.",
            "Promotes update and restore while keeping Open App, Finder, source, skip, and ignore visible."
        ]),
        UpkeepRelease(version: "0.14.8", date: "21 July 2026", changes: [
            "Tightens list versions into compact current → new groups while retaining aligned actions.",
            "Refreshes the open-app header with larger artwork, versions beneath the title, and source below.",
            "Removes the duplicated version transition from the status card.",
            "Adds a full-width clickable and copyable source URL."
        ]),
        UpkeepRelease(version: "0.14.7", date: "21 July 2026", changes: [
            "Aligns current versions, arrows, new versions, and actions into fixed list columns.",
            "Keeps version positions stable by reserving the package and model action column.",
            "Opens the detected update source, including the correct Homebrew cask page.",
            "Uses explicit Open Homebrew, Open GitHub, Open Sparkle Feed, and Open App Store labels."
        ]),
        UpkeepRelease(version: "0.14.6", date: "21 July 2026", changes: [
            "Shows update versions as one current → new transition throughout inventory lists.",
            "Increases shared row typography and vertical spacing for easier scanning.",
            "Applies a larger minimum Dynamic Type size across the interface while respecting accessibility settings."
        ]),
        UpkeepRelease(version: "0.14.5", date: "21 July 2026", changes: [
            "Removes the redundant Current label from installed inventory rows.",
            "Sorts apps with detected updates to the top of All Apps, source, and Adoptable lists.",
            "Sorts outdated Homebrew, developer, and AI model packages above current items by default."
        ]),
        UpkeepRelease(version: "0.14.4", date: "21 July 2026", changes: [
            "Removes separators between list items throughout the app.",
            "Replaces the app inspector’s Controls menu with visible action buttons.",
            "Shows only the new version number in update status columns.",
            "Left-aligns the selected app’s version transition without list-column indentation."
        ]),
        UpkeepRelease(version: "0.14.3", date: "21 July 2026", changes: [
            "Moves the Running state beside the app name in rows and the inspector title.",
            "Keeps the app shown in the inspector visibly selected and closes stale details when changing workspaces.",
            "Uses shared identity, status, and version columns across app, package, model, macOS, and history lists.",
            "Synchronizes package and model detail panes with their selected row."
        ]),
        UpkeepRelease(version: "0.14.2", date: "21 July 2026", changes: [
            "Standardizes app, package, model, macOS, and history rows around the same compact detail hierarchy.",
            "Replaces technical metadata and oversized badges with one useful source or type line.",
            "Removes duplicate row menus where the adjacent detail pane already provides the complete control set."
        ]),
        UpkeepRelease(version: "0.14.1", date: "21 July 2026", changes: [
            "Simplifies update rows by removing release-note previews and repeated source badges.",
            "Keeps package and model rows focused on identity, type or runtime, version, and action.",
            "Removes the redundant app-row More menu now that the side inspector contains every control."
        ]),
        UpkeepRelease(version: "0.14.0", date: "21 July 2026", changes: [
            "Replaces modal app details with a resizable side inspector beside app and update lists.",
            "Removes small GroupBox legends and uses clearer status, controls, What’s New, Homebrew, and information sections.",
            "Closes app details automatically when moving into non-app workspaces."
        ]),
        UpkeepRelease(version: "0.13.0", date: "21 July 2026", changes: [
            "Redesigned app details with a larger native layout, clearer status summary, and structured sections.",
            "Consolidates update, adoption, exclusion, launch, Finder, and update-source actions in one dialog.",
            "Shows complete release notes and expanded application and source metadata."
        ]),
        UpkeepRelease(version: "0.12.1", date: "21 July 2026", changes: [
            "Records scan warnings in Diagnostics for full and targeted scans.",
            "Adds Homebrew adoption to app details, including Update & Adopt when a newer cask is available."
        ]),
        UpkeepRelease(version: "0.12.0", date: "21 July 2026", changes: [
            "Shows live Running indicators in app lists, update rows, app details, and the Adoptable workspace.",
            "Asks before Homebrew changes a running GUI app and quits it gracefully before updating.",
            "Preflights batch Homebrew updates and handles all affected running apps in one confirmation.",
            "Stops safely with actionable guidance when an app does not quit cleanly."
        ]),
        UpkeepRelease(version: "0.11.3", date: "21 July 2026", changes: [
            "Distinguishes genuine up-to-date results from update-source and package-manager scan failures.",
            "Preserves last-known updates only for the affected app or source when part of a scan fails.",
            "Records actionable network, HTTP, timeout, malformed-data, and command failures in Diagnostics.",
            "Retries Homebrew lock contention and verifies inventory after update commands complete.",
            "Refined the app icon with rounded, appearance-aware artwork and added developer details to About.",
            "Restored test compatibility with standalone Apple Command Line Tools and added reliability coverage."
        ]),
        UpkeepRelease(version: "0.11.2", date: "21 July 2026", changes: [
            "Removed the requirement for Ollama or LM Studio to be running during model update checks.",
            "Reads Ollama’s manifest store directly and compares exact content digests with its registry.",
            "Detects LM Studio’s configured model directory as well as its standard legacy locations.",
            "Uses runtime command-line tools only when installing an update or as a compatibility fallback."
        ]),
        UpkeepRelease(version: "0.11.1", date: "21 July 2026", changes: [
            "Rebuilt every item list around one shared native row layout.",
            "Anchored versions, status labels, action buttons, and More menus to consistent right-side columns.",
            "Standardized icon size, text hierarchy, spacing, and control sizing across all item types.",
            "Prevented long descriptions from shifting actions or producing mismatched row designs."
        ]),
        UpkeepRelease(version: "0.11.0", date: "21 July 2026", changes: [
            "Standardized app, package, model, update, and history rows around a compact native macOS list layout.",
            "Aligned installed and available versions into a consistent, monospaced trailing column for faster scanning.",
            "Reduced oversized icons and repeated prominent buttons while consolidating secondary actions into a single More menu.",
            "Improved current, skipped, and ignored status presentation across installed-item lists."
        ]),
        UpkeepRelease(version: "0.10.1", date: "21 July 2026", changes: [
            "Removed duplicate toolbar titles, the selectable sidebar branding row, and the persistent bottom status strip.",
            "Rebuilt Settings with standard sidebar navigation and restored the menu-bar visibility control.",
            "Reduced repetitive app status text and corrected About to show the installed version dynamically.",
            "Converted macOS updates and installers to standard inset list sections and removed more custom content chrome."
        ]),
        UpkeepRelease(version: "0.10.0", date: "21 July 2026", changes: [
            "Refreshed the interface for Apple’s latest macOS design language and automatic Liquid Glass adoption.",
            "Replaced custom content chrome and card stacks with standard split-view, toolbar, sidebar, search, and inset-list patterns.",
            "Simplified toolbar actions, strengthened typography and section hierarchy, and improved icon accessibility.",
            "Reduced decorative color and custom backgrounds so system materials adapt to appearance and accessibility settings."
        ]),
        UpkeepRelease(version: "0.9.7", date: "21 July 2026", changes: [
            "Fixed a 100% CPU launch hang on macOS 27 caused by recursive SwiftUI NSHostingView environment propagation in MenuBarExtra.",
            "Replaced the unstable menu-bar scene with a direct AppKit status item implemented in Swift.",
            "Preserved menu-bar visibility and count settings, update actions, tooltip, and Dock badge."
        ]),
        UpkeepRelease(version: "0.9.6", date: "21 July 2026", changes: [
            "Fixed a launch crash on macOS 27 caused by recursive SwiftUI scene updates in the custom application command block.",
            "Removed redundant Settings and refresh command overrides; Settings remains available through the app menu and menu-bar extra.",
            "Simplified the SwiftUI scene graph while retaining the menu-bar update counter and Dock badge."
        ]),
        UpkeepRelease(version: "0.9.5", date: "21 July 2026", changes: [
            "Rebuilt the menu-bar item as a native SwiftUI MenuBarExtra with a reliable system-symbol label, live count, tooltip, and controls.",
            "Restored the menu-bar item once for existing installations that had previously hidden it, while keeping the setting user-controlled afterward.",
            "Simplified Dock badging to the smallest required NSDockTile bridge because SwiftUI has no macOS Dock-badge API."
        ]),
        UpkeepRelease(version: "0.9.4", date: "21 July 2026", changes: [
            "Replaced the SwiftUI menu-bar extra with a direct AppKit status item showing the Upkeep icon, count, tooltip, and controls.",
            "Replaced the system-dependent Dock badge with a high-contrast counter drawn directly on the Dock icon.",
            "Kept menu-bar, toolbar, sidebar, notification, and Dock counts synchronized."
        ]),
        UpkeepRelease(version: "0.9.3", date: "21 July 2026", changes: [
            "Added a prominent live update counter directly to the main toolbar.",
            "The toolbar counter opens the Updates workspace and includes an explanatory tooltip.",
            "Toolbar, sidebar, menu bar, notifications, and Dock now share the same filtered count."
        ]),
        UpkeepRelease(version: "0.9.2", date: "21 July 2026", changes: [
            "Fixed Dock badges by explicitly installing and redrawing Upkeep’s application Dock tile.",
            "Made Upkeep enforce regular-app activation so its Dock icon and standard hover label remain available.",
            "Refreshes the Dock icon and filtered update count whenever Upkeep becomes active."
        ]),
        UpkeepRelease(version: "0.9.1", date: "21 July 2026", changes: [
            "Restored a standard unified macOS toolbar with a visible window title and current workspace label.",
            "Added a live Dock icon badge showing the filtered number of available updates.",
            "The Dock badge now clears at zero and responds immediately to scans, skips, ignores, and restores."
        ]),
        UpkeepRelease(version: "0.9.0", date: "21 July 2026", changes: [
            "Added official Ollama and LM Studio runtime logos with an automatic generic-icon fallback.",
            "Added Skip This Version and Ignore Updates controls for apps, packages, and local models.",
            "Added an Ignored Settings section for reviewing and restoring every exclusion.",
            "Excluded items no longer appear in the Updates workspace or contribute to update counts."
        ]),
        UpkeepRelease(version: "0.8.0", date: "21 July 2026", changes: [
            "Added update discovery and native update actions for locally installed Ollama and LM Studio models.",
            "Moved the changelog into Settings and removed Settings and Changelog from the sidebar.",
            "Removed the repository shortcut from the app and project documentation."
        ]),
        UpkeepRelease(version: "0.7.0", date: "21 July 2026", changes: [
            "Added a new original Upkeep app icon across the Dock, sidebar, app bundle, and menu bar.",
            "Added a menu-bar status item with a live update count, tooltip, quick scan, Settings, and app controls.",
            "Added persistent General, Sources, Developer, notification, beta, and refresh settings.",
            "Replaced manual version entry with registry-backed version menus that default to the latest release.",
            "Added all-manager and individual package-manager refresh controls in the Developer view."
        ]),
        UpkeepRelease(version: "0.6.0", date: "21 July 2026", changes: [
            "Added bundled package-manager artwork for Homebrew, npm, pnpm, Python, RubyGems, and Cargo.",
            "Made installed apps and developer packages clickable with complete detail views.",
            "Added explicit version installation for npm, pnpm, pip, RubyGems, and Cargo packages.",
            "Added this in-app changelog and the project’s complete release history."
        ]),
        UpkeepRelease(version: "0.5.0", date: "21 July 2026", changes: [
            "Added installed-only npm, pnpm, Python/pip, RubyGems, and Cargo sections.",
            "Kept current developer packages visible and included outdated packages in the update count.",
            "Counted newer Homebrew casks for matching unmanaged apps."
        ]),
        UpkeepRelease(version: "0.4.0", date: "21 July 2026", changes: [
            "Added macOS stable updates, beta enrollment, and compatible full-installer discovery.",
            "Added update history, pre-update app backups, and direct app rollback where supported.",
            "Added recovery guidance for package and macOS updates that cannot be reverted automatically."
        ]),
        UpkeepRelease(version: "0.3.0", date: "21 July 2026", changes: [
            "Added Homebrew formula and cask inventory, filters, package details, and batch updates.",
            "Added Homebrew adoption for compatible apps and dependency visibility."
        ]),
        UpkeepRelease(version: "0.2.0", date: "21 July 2026", changes: [
            "Added GitHub Releases and Electron metadata checking.",
            "Added source filters, update counters, and automatic checking on app launch."
        ]),
        UpkeepRelease(version: "0.1.0", date: "21 July 2026", changes: [
            "Created the native SwiftUI macOS app scanner.",
            "Added Mac App Store and Sparkle update discovery."
        ])
    ]
}
