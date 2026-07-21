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
