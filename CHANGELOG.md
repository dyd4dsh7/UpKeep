# Changelog

All notable changes to Upkeep are documented here.

## 0.23.1 — 2026-07-22

- Prevented stale update candidates from surviving a failed source check after an app was updated elsewhere.
- Prevented Homebrew candidates from replacing TestFlight, Setapp, or Microsoft AutoUpdate-managed apps.
- Corrected prerelease detection for stable platform-qualified versions and restored them to version menus.
- Preserved scheduled-check timing across relaunches and restored Sparkle release notes delivered as CDATA.
- Added bounded rollback-backup retention, failed-update cleanup, corrupt-history protection, and accurate expired-backup states.
- Corrected the managed-updater launch error message and expanded regression coverage for every fix.

## 0.23.0 — 2026-07-22

- Added persistent diagnostics for scan timing, source requests, version decisions, Homebrew commands, and update results.
- Added an at-a-glance diagnostics dashboard, structured entry cards, searchable severity and category filters, plus export and clear controls in Settings.
- Made scan durations and status values easier to read, with warning and error totals scoped to the latest completed scan.
- Redacted credentials, authenticated URLs, URL queries, and the user's home-directory path before diagnostics are written to disk or exported.
- Bounded the local diagnostics history and added privacy and persistence test coverage.

## 0.22.0 — 2026-07-22

- Added compact icon menus for sorting, filtering, and list density, grouped with consistent spacing at the far-left edge of each list toolbar.
- Kept batch update actions on the far right and moved search into the sidebar.
- Replaced list-scoped search with global results across apps, packages, models, macOS, warnings, and update history.
- Added Default, A–Z, Z–A, install-date, recently-updated, source, and version sorting where applicable.
- Added app filters for available updates, source warnings, and unmapped applications, with warning-severity sorting and inline issue indicators.
- Added an Unmapped Homebrew filter for casks without a matching application bundle.
- Added persisted Comfortable and Compact list densities, available from list controls and Settings.
- Added a complete warnings-only view so every source failure remains inspectable beyond the summary banner.

## 0.21.0 — 2026-07-22

- Distinguished TestFlight builds from Mac App Store releases and routed them back to TestFlight for updates.
- Detected Setapp editions and Microsoft AutoUpdate registrations without misclassifying other Microsoft applications.
- Prevented externally managed editions from receiving incompatible App Store, Sparkle, GitHub, or Homebrew-adoption actions.
- Recognized Sparkle package installers and opened the app's built-in updater while retaining the developer download as a secondary action.
- Added update-management badges, explanations, and manager shortcuts to app details.
- Added dedicated TestFlight, Setapp, and Microsoft AutoUpdate categories with live counts to the sidebar.
- Added source-aware empty states with refresh and clear-search actions to application categories.
- Unified sidebar, page-header, empty-state, and update-action iconography with destination-specific SF Symbols.

## 0.20.0 — 2026-07-22

- Added a unified review sheet for selecting application, Homebrew, developer-package, and local-model updates.
- Runs selected updates sequentially, continues after individual failures, and presents a complete results summary.
- Clearly identifies actions that must be completed in the App Store, Sparkle, or GitHub and keeps macOS installation separate.
- Deduplicates Homebrew-backed application updates so the same cask cannot be selected twice.

## 0.19.0 — 2026-07-22

- Added one-to-six-day, one-week, and one-, three-, and six-month time frames for both Skip and Ignore actions.
- Timed skips remain version-specific, while timed ignores suppress every version until they expire.
- Automatically restores expired updates and shows temporary exclusion deadlines in Settings.
- Made application exclusions survive app moves and migrated existing path-based exclusions.

## 0.18.0 — 2026-07-22

- Added precise daily update checks with a user-selected time and a visible next-check date.
- Replaced periodic polling with an efficient single-run scheduler that immediately follows preference changes.
- Added a persistent option to hide the available-update count from the Dock icon.

## 0.17.0 — 2026-07-22

- Retained every App Store, Homebrew, Sparkle, and GitHub source that reports an available update instead of stopping at the first match.
- Added a deterministic preferred-source policy while keeping alternate source versions and actions available from app details.
- Checked GitHub releases alongside Sparkle feeds and displayed all detected sources throughout app lists and details.
- Preserved last-known candidates for individual sources when a later scan partially fails.
- Added coverage for multi-source merging, preferred-source ordering, Homebrew adoption priority, and duplicate-source version selection.

## 0.16.0 — 2026-07-21

- Added an opt-in prerelease setting for apps, packages, and macOS updates, with a confirmation warning before enabling potentially unstable releases.
- Added Alpha, Beta, RC, Preview, Nightly, Dev, and Prerelease badges throughout update and inventory lists, including recognition of an already-installed prerelease when the setting is off.
- Filtered prerelease and platform-specific package builds from version menus unless prereleases are enabled, while preserving the installed version for recovery or replacement.
- Improved GitHub and Sparkle channel detection, semantic and calendar version ordering, and deterministic package-version sorting.
- Fixed npm and pnpm discovery and commands when Upkeep launches outside a terminal, including NVM and pnpm environment paths.

## 0.15.0 — 2026-07-21

- Kept the Updates workspace selected when opening Homebrew, developer-package, or AI-model update details.
- Added update-specific package and model selection so the chosen row remains highlighted.
- Reused the complete package and model detail views as side inspectors beside the Updates list.

## 0.14.9 — 2026-07-21

- Removed the raw source URL bar from app details.
- Rebuilt app actions as a responsive grid of large capsule buttons.
- Promoted update and restore to a clear blue primary action while keeping Open App, Finder, source, skip, and ignore directly visible.

## 0.14.8 — 2026-07-21

- Tightened list version transitions into compact current → new groups while retaining aligned action columns.
- Refreshed the open-app inspector header with larger artwork, the version transition beneath the title, and the source directly below it.
- Removed the duplicated version transition from the status card.
- Added a full-width clickable source URL with a copy action.

## 0.14.7 — 2026-07-21

- Aligned current versions, arrows, new versions, and update actions into fixed columns across inventory and update lists.
- Reserved the action column for current package and model rows so version positions remain stable throughout each list.
- Corrected app source links to open the detected source, including Homebrew cask pages instead of unrelated fallback feeds.
- Renamed generic source actions to explicit Open Homebrew, Open GitHub, Open Sparkle Feed, and Open App Store labels.

## 0.14.6 — 2026-07-21

- Displayed update versions as a single current → new transition across app, Homebrew, developer package, and AI model inventories.
- Increased shared row title, subtitle, status, and version typography with more vertical breathing room.
- Applied a larger minimum Dynamic Type size throughout the interface while continuing to respect larger accessibility settings.

## 0.14.5 — 2026-07-21

- Removed the redundant Current label from installed app, Homebrew, developer package, and AI model rows.
- Sorted apps with detected updates to the top of All Apps, source, and Adoptable lists by default.
- Sorted outdated Homebrew, developer, and AI model packages above current items while preserving alphabetical order within each group.

## 0.14.4 — 2026-07-21

- Removed separators between list items across app, package, model, macOS, and history workspaces.
- Replaced the app inspector’s Controls menu with visible Open, Finder, source, skip, and ignore buttons.
- Shortened update status columns to display only the new version number.
- Left-aligned the selected app’s installed-to-new version transition instead of reserving list-column spacing.

## 0.14.3 — 2026-07-21

- Moved the Running state beside the app name in list rows and the inspector title.
- Added native app-row selection so the app shown in the inspector remains visibly highlighted, and closes stale details when switching workspaces.
- Unified installed app, Homebrew, developer package, AI model, macOS, and history rows with shared identity, status, and version columns.
- Synchronized package and model detail panes with their selected list row.

## 0.14.2 — 2026-07-21

- Standardized installed app, adoptable app, Homebrew, developer package, AI model, macOS, and history rows around the same compact detail hierarchy.
- Replaced technical bundle IDs, paths, prose descriptions, and oversized status badges with a single useful source or type line.
- Removed duplicate row menus where the adjacent detail pane already exposes the complete control set; advanced actions remain available from details and context menus.

## 0.14.1 — 2026-07-21

- Simplified update rows for the narrower inspector layout by removing release-note previews and repeated source badges.
- Reduced package and model rows to essential identity, type or runtime, version, and action information.
- Removed the redundant app-row More menu because the side inspector now contains the complete control set.

## 0.14.0 — 2026-07-21

- Replaced modal app details with a resizable side inspector that remains alongside app and update lists.
- Removed the small GroupBox legends and reorganized details around status, controls, What's New, Homebrew, and information sections.
- Automatically closes the app inspector when navigating to package, model, macOS, or history workspaces.

## 0.13.0 — 2026-07-21

- Redesigned app details as a larger native dialog with a clearer identity header, update-status summary, and structured sections.
- Consolidated every per-app action into the dialog: update, update and adopt, adopt, skip, ignore, restore, open, reveal in Finder, and source links.
- Added complete release notes and expanded technical and update-source metadata to app details.

## 0.12.1 — 2026-07-21

- Added a dismiss control for scan warnings; dismissed warnings return after the next full or targeted scan.
- Added Homebrew adoption to app details, including a clear Update & Adopt action when a newer cask is available.

## 0.12.0 — 2026-07-21

- Added live Running indicators to installed apps, available updates, app details, and adoptable apps.
- Added a confirmation step before Homebrew changes a running GUI app, with graceful app termination before the update begins.
- Added batch-update preflight that identifies and quits all affected running apps together.
- Stops the update with actionable guidance when an app does not quit cleanly.

## 0.11.3 — 2026-07-21

- Distinguished genuine “up to date” results from App Store, Sparkle, GitHub, Homebrew, macOS, developer-package, and AI-model scan failures.
- Preserved last-known updates only for the app or source that failed, while keeping disabled-source behavior unchanged.
- Added compact in-app scan warnings with actionable network, HTTP, timeout, malformed-data, and command failure messages.
- Added Homebrew lock-contention retries, post-update reconciliation, and separate inventory and cask-catalog health tracking.
- Refined the app icon with rounded, appearance-aware artwork and added developer details to About.
- Restored test-suite compatibility with standalone Apple Command Line Tools and added reliability regression coverage.

## 0.11.2 — 2026-07-21

- Removed the requirement for Ollama or LM Studio to be running during model update checks.
- Reads Ollama's installed manifest store directly and compares its exact content digest with the registry.
- Detects LM Studio's configured model directory from its settings, with support for standard legacy locations.
- Retains runtime CLI commands only for installing updates, with CLI discovery as a compatibility fallback.

## 0.11.1 — 2026-07-21

- Rebuilt every item list around one shared native row layout.
- Anchored versions, status labels, action buttons, and More menus to consistent right-side columns.
- Standardized 36-point icons, title and subtitle hierarchy, spacing, and control sizing across apps, packages, models, macOS updates, history, adoptable apps, and exclusions.
- Prevented long descriptions from shifting actions or producing mismatched row designs.

## 0.11.0 — 2026-07-21

- Standardized app, package, model, update, and history rows around a compact native macOS list layout.
- Aligned installed and available versions into a consistent, monospaced trailing column for faster scanning.
- Reduced oversized icons and repeated prominent buttons while consolidating secondary actions into a single More menu.
- Improved current, skipped, and ignored status presentation across installed-item lists.

## 0.10.1 — 2026-07-21

- Removed duplicate toolbar titles, the selectable sidebar branding row, and the persistent bottom status strip.
- Rebuilt Settings with standard sidebar navigation and restored the menu-bar visibility control.
- Reduced repetitive app status text and corrected the About screen to show the installed version dynamically.
- Converted macOS updates and installers to standard inset list sections and removed more custom bar and card backgrounds.

## 0.10.0 — 2026-07-21

- Refreshed the interface for Apple’s latest macOS design language and automatic Liquid Glass adoption.
- Replaced custom content chrome and card stacks with standard split-view, toolbar, sidebar, search, and inset-list patterns.
- Simplified toolbar actions, strengthened typography and section hierarchy, and improved icon accessibility.
- Reduced decorative color and custom backgrounds so system materials adapt to appearance and accessibility settings.

## 0.9.7 — 2026-07-21

- Fixed a 100% CPU launch hang on macOS 27 caused by recursive SwiftUI `NSHostingView` environment propagation in `MenuBarExtra`.
- Replaced the unstable menu-bar scene with a direct AppKit status item implemented in Swift.
- Preserved the menu-bar visibility and count settings, update actions, tooltip, and Dock badge.

## 0.9.6 — 2026-07-21

- Fixed a launch crash on macOS 27 caused by recursive SwiftUI scene updates in the custom application command block.
- Removed redundant Settings and refresh command overrides; Settings remains available through the system-generated app menu and the menu-bar extra.
- Simplified the SwiftUI scene graph while retaining the menu-bar update counter and Dock badge.

## 0.9.5 — 2026-07-21

- Rebuilt the menu-bar item as a native SwiftUI `MenuBarExtra` with a reliable system-symbol label, live count, tooltip, and controls.
- Restored the menu-bar item once for existing installations that had previously hidden it while preserving the user-controlled setting afterward.
- Simplified Dock badging to the smallest required `NSDockTile.badgeLabel` bridge because SwiftUI does not provide a macOS Dock-badge API.

## 0.9.4 — 2026-07-21

- Replaced the SwiftUI menu-bar extra with a direct AppKit status item containing the Upkeep icon, live count, tooltip, and app controls.
- Replaced the system-dependent Dock badge with a high-contrast count drawn directly onto the Dock icon.
- Kept all visible count surfaces synchronized to the filtered update total.

## 0.9.3 — 2026-07-21

- Added a prominent live available-update counter to the main toolbar.
- Made the toolbar counter open the Updates workspace and expose a descriptive tooltip.
- Unified the toolbar, sidebar, menu-bar, notification, and Dock counts.

## 0.9.2 — 2026-07-21

- Fixed Dock badge rendering by explicitly installing and redrawing the application Dock tile.
- Enforced regular-app activation so the Dock icon and its standard Upkeep hover label remain available.
- Refreshes the Dock tile whenever the app becomes active or the filtered update count changes.

## 0.9.1 — 2026-07-21

- Restored a standard unified macOS toolbar for the main app window.
- Added a live Dock icon badge for the filtered available-update count.
- Made the Dock badge react immediately to scans and exclusion changes, and clear automatically at zero.

## 0.9.0 — 2026-07-21

- Added official Ollama and LM Studio logos with a generic fallback icon.
- Added version-specific skipping and persistent update ignoring for apps, Homebrew packages, developer packages, and local models.
- Added an Ignored Settings section where exclusions can be restored individually or together.
- Removed skipped and ignored items from the Updates workspace and update counters.

## 0.8.0 — 2026-07-21

- Added update discovery for locally installed Ollama and LM Studio models.
- Added model details and native update actions through `ollama pull` and `lms get`.
- Moved the in-app changelog into Settings and removed Settings and Changelog from the sidebar.
- Removed the repository shortcut from the app and project documentation.

## 0.7.0 — 2026-07-21

- Added a new original Upkeep app icon across the Dock, sidebar, app bundle, and menu bar.
- Added a menu-bar status item with a live update count, tooltip, quick scan, Settings, and app controls.
- Added persistent General, Sources, Developer, notification, beta, and refresh settings.
- Replaced manual version entry with registry-backed version menus that default to the latest release.
- Added all-manager and individual package-manager refresh controls in the Developer view.

## 0.6.0 — 2026-07-21

- Added bundled package-manager artwork for Homebrew, npm, pnpm, Python, RubyGems, and Cargo.
- Made installed apps and developer packages clickable with complete detail views.
- Added explicit version installation for npm, pnpm, pip, RubyGems, and Cargo packages.
- Added an in-app changelog and complete local release history.

## 0.5.0 — 2026-07-21

- Added installed-only npm, pnpm, Python/pip, RubyGems, and Cargo sections.
- Kept current developer packages visible and included outdated packages in the update count.
- Counted newer Homebrew casks for matching unmanaged apps.

## 0.4.0 — 2026-07-21

- Added macOS stable updates, beta enrollment, and compatible full-installer discovery.
- Added update history, pre-update app backups, and direct app rollback where supported.
- Added recovery guidance for package and macOS updates that cannot be reverted automatically.

## 0.3.0 — 2026-07-21

- Added Homebrew formula and cask inventory, filters, package details, and batch updates.
- Added Homebrew adoption for compatible apps and dependency visibility.

## 0.2.0 — 2026-07-21

- Added GitHub Releases and Electron metadata checking.
- Added source filters, update counters, and automatic checking on app launch.

## 0.1.0 — 2026-07-21

- Created the native SwiftUI macOS app scanner.
- Added Mac App Store and Sparkle update discovery.
