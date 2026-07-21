import SwiftUI

struct ChangelogView: View {
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            if !compact {
                HeaderView(
                    title: "Changelog",
                    subtitle: "What’s new in Upkeep",
                    systemImage: "list.bullet.rectangle.fill"
                )
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(UpkeepRelease.all) { release in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Upkeep \(release.version)").font(.title2.bold())
                                if release.version == UpkeepRelease.all.first?.version {
                                    Text("CURRENT").font(.caption2.bold()).foregroundStyle(.blue)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(.blue.opacity(0.12), in: Capsule())
                                }
                                Spacer()
                                Text(release.date).foregroundStyle(.secondary)
                            }
                            ForEach(release.changes, id: \.self) { change in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).padding(.top, 2)
                                    Text(change).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(20)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(compact ? 8 : 24).frame(maxWidth: 850)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct UpkeepRelease: Identifiable {
    var id: String { version }
    let version: String
    let date: String
    let changes: [String]

    static let all = [
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
            "Lets you hide scan warnings until the next full or targeted scan.",
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
            "Shows compact, actionable warnings for network, HTTP, timeout, malformed-data, and command failures.",
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
