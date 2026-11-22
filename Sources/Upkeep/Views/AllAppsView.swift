import AppKit
import SwiftUI

struct AllAppsView: View {
    @UpkeepStoreReference private var store
    let apps: [InstalledApp]
    let title: String
    let systemImage: String
    @UpkeepState private var projection = AllAppsProjection()

    var body: some View {
        let visibleApps = displayedApps
        let duplicateBundleIDs = projection.duplicateBundleIDs(in: store.apps, generation: store.library.appGeneration)
        VStack(spacing: 0) {
            if visibleApps.isEmpty {
                emptyState
                    .upkeepStateTransition()
            } else {
                List(selection: selectedAppID) {
                    ForEach(visibleApps) { app in
                    let update = store.update(for: app)
                    let visibleUpdate = store.visibleUpdate(for: app)
                    let exclusion = activeExclusion(for: app, update: update)
                    let hasAdoptionOption = hasHomebrewAdoptionOption(for: app, update: update)
                    StandardItemRow(isSelected: store.selectedApp?.id == app.id) {
                        AppIcon(url: app.url, size: 36)
                    } content: {
                        ItemIdentityView(
                            title: app.name,
                            detail: sourceSummary(for: app) + (app.bundleIdentifier.map(duplicateBundleIDs.contains) == true ? " · " + app.url.deletingLastPathComponent().path : ""),
                            isRunning: store.isRunning(app),
                            prereleaseChannel: update?.prereleaseChannel ?? app.prereleaseChannel,
                            prereleaseIsInstalled: update?.prereleaseIsInstalled ?? (app.prereleaseChannel != nil),
                            showsIntelWarning: app.needsAppleSiliconMigration,
                            cveItem: CVEInventoryItem(app)
                        )
                    } accessories: {
                        if store.isRefreshing(app) {
                            RefreshingIndicator(itemName: app.name)
                        }
                        UpdateVersionAccessory(
                            currentVersion: app.installedVersion,
                            availableVersion: visibleUpdate?.availableVersion ?? app.installedVersion,
                            showsUpdate: visibleUpdate != nil,
                            exclusion: exclusion
                        )
                    }
                    .tag(app.id)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if let update {
                            Button(update.actionTitle) { Task { await store.performUpdate(update) } }
                                .disabled(store.isUpdating(update))
                        }
                        Button("Refresh") { Task { await store.refresh(app) } }
                            .disabled(store.isWorking(.applicationRefresh(app.id)))
                        Divider()
                        if let exclusion {
                            Button("Restore Updates") { store.restore(exclusion) }
                        } else {
                            if let update {
                                UpdateExclusionOptions(
                                    skipTitle: "Skip Version \(update.displayAvailableVersion)",
                                    ignoreTitle: "Ignore \(app.name) Indefinitely",
                                    skip: { store.skip(update) }, ignore: { store.ignore(app) },
                                    skipFor: { store.skip(update, duration: $0) },
                                    ignoreFor: { store.ignore(app, duration: $0) }
                                )
                            } else {
                                Menu("Ignore") {
                                    Button("Ignore \(app.name) Indefinitely") { store.ignore(app) }
                                    Divider()
                                    ForEach(UpdateExclusionDuration.allCases) { duration in
                                        Button("For \(duration.title)") { store.ignore(app, duration: duration) }
                                    }
                                }
                            }
                        }
                        if hasAdoptionOption {
                            if store.isHomebrewAdoptionIgnored(app) {
                                Button("Restore Homebrew Adoption") { store.restoreHomebrewAdoption(app) }
                            } else {
                                Button("Ignore Homebrew Adoption") { store.ignoreHomebrewAdoption(app) }
                            }
                        }
                        Divider()
                        Button("Open") { NSWorkspace.shared.open(app.url) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                        Button("View Details") { store.selectedApp = app }
                    }
                    }
                }
                .upkeepContentList()
                .upkeepStateTransition()
            }
        }
        .upkeepAnimated(for: visibleApps.map(\.id))
        .safeAreaInset(edge: .top, spacing: 0) {
            WorkspaceSummary(title: title,
                detail: "\(WorkspaceSummary.count(visibleApps.count, "application", "applications")) · \(WorkspaceSummary.count(visibleApps.filter { store.visibleUpdate(for: $0) != nil }.count, "update", "updates")) available",
                systemImage: systemImage)
        }
        .toolbar { listToolbar }
    }

    private func hasHomebrewAdoptionOption(
        for app: InstalledApp,
        update: AvailableUpdate?
    ) -> Bool {
        store.adoptableApp(for: app) != nil ||
            update?.candidates.contains(where: \.requiresHomebrewAdoption) == true
    }

    @ToolbarContentBuilder private var listToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            appSortMenu
            appFilterMenu
        }
        upkeepToolbarSpacer()
        ToolbarItem(placement: .primaryAction) {
            ScanToolbarButton()
        }
    }

    private var appSortMenu: some View {
        Menu {
            Section("Sort") {
                appSortButton("Default", order: .recommended)
                appSortButton("Name: A–Z", order: .name)
                appSortButton("Name: Z–A", order: .name, ascending: false)
                appSortButton("Install Date", order: .installDate, ascending: false)
                appSortButton("Recently Updated", order: .recentlyUpdated, ascending: false)
                appSortButton("Update Source", order: .source)
                appSortButton("Installed Version", order: .installedVersion)
                appSortButton("Available Version", order: .availableVersion)
            }
        } label: {
            ListControlLabel(
                systemImage: "list.bullet",
                isActive: store.appSortOrder != .recommended
            )
        }
        .menuIndicator(.hidden)
        .toolbarControlLabel("Sort applications")
    }

    private var appFilterMenu: some View {
        Menu {
            Section("Status") {
                appFilterButton(.all)
                appFilterButton(.updates)
                appFilterButton(.adoptable)
                appFilterButton(.unmapped)
            }
            Section("Update Source") {
                appFilterButton(.appStore)
                appFilterButton(.testFlight)
                appFilterButton(.setapp)
                appFilterButton(.microsoftAutoUpdate)
                appFilterButton(.homebrew)
                appFilterButton(.sparkle)
                appFilterButton(.github)
            }
        } label: {
            ListControlLabel(
                systemImage: "line.3.horizontal.decrease",
                isActive: store.appListFilter != .all
            )
        }
        .menuIndicator(.hidden)
        .toolbarControlLabel("Filter applications")
    }

    private func appFilterButton(_ filter: AppListFilter) -> some View {
        Button {
            store.appListFilter = filter
        } label: {
            MenuSelectionLabel(title: filter.rawValue, isSelected: store.appListFilter == filter)
        }
    }

    private func appSortButton(_ title: String, order: AppSortOrder, ascending: Bool = true) -> some View {
        Button {
            store.appSortOrder = order
            store.appSortAscending = ascending
        } label: {
            MenuSelectionLabel(
                title: title,
                isSelected: store.appSortOrder == order &&
                    (order == .recommended || store.appSortAscending == ascending)
            )
        }
    }

    @ViewBuilder private var emptyState: some View {
        if store.isScanning && store.searchText.isEmpty {
            WorkspaceScanningState(
                title: store.appListFilter == .updates ? "Checking for updates…" : "Finding apps…",
                detail: "Results appear here when the current check finishes."
            )
        } else {
            populatedEmptyState
        }
    }

    private var populatedEmptyState: some View {
        WorkspaceEmptyState(title: emptyTitle, systemImage: emptySystemImage,
                            description: Text(emptyDescription)) {
            if store.searchText.isEmpty {
                Button("Check Again") { Task { await store.scan() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isScanning)
            } else {
                Button("Clear Search") { store.searchText = "" }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if store.appListFilter == .unmapped { return "Every App Is Mapped" }
        if store.appListFilter == .updates { return "No App Updates" }
        if store.appListFilter == .adoptable { return "No Homebrew Suggestions" }
        if !store.searchText.isEmpty { return "No Matching Apps" }
        return switch title {
        case "Setapp": "No Setapp Apps"
        case "TestFlight": "No TestFlight Apps"
        case "Microsoft AutoUpdate": "No Microsoft Apps"
        case "No Source": "Every App Has a Source"
        case "All Apps": "No Apps Found"
        case "Other Updaters": "No Apps With Other Updaters"
        default: title.hasSuffix("Apps") ? "No \(title)" : "No \(title) Apps"
        }
    }

    private var emptyDescription: String {
        if store.appListFilter == .unmapped { return "Every app in this list has a supported source or external update manager." }
        if store.appListFilter == .updates { return "No apps in this list currently have an available update." }
        if store.appListFilter == .adoptable { return "No installed apps can currently be moved under Homebrew management." }
        if !store.searchText.isEmpty {
            return "No apps in \(title) match “\(store.searchText)”."
        }
        return switch title {
        case "Setapp": "No installed apps managed by Setapp were detected."
        case "TestFlight": "No installed TestFlight beta apps were detected."
        case "Microsoft AutoUpdate": "No installed apps managed by Microsoft AutoUpdate were detected."
        case "No Source": "Every installed app has a supported update source or update manager."
        case "All Apps": "Upkeep didn’t find any installed apps. Check again to rescan."
        default: "No installed apps associated with \(title) were detected."
        }
    }

    private var emptySystemImage: String {
        if store.appListFilter == .unmapped { return "link.badge.plus" }
        return title == "No Source" ? "checkmark.seal" : systemImage
    }

    /// Filtered and sorted once per inventory/filter/sort change, not per body.
    private var displayedApps: [InstalledApp] {
        let library = store.library
        let key = AllAppsProjection.Key(
            apps: apps, appGeneration: library.appGeneration, updateGeneration: library.primaryUpdateGeneration,
            homebrewGeneration: library.homebrewGeneration, adoptableGeneration: library.adoptableGeneration,
            filter: store.appListFilter, sortOrder: store.appSortOrder, ascending: store.appSortAscending)
        return projection.values(for: key, build: sortedFilteredApps)
    }

    private func sortedFilteredApps() -> [InstalledApp] {
        let sortOrder = store.appSortOrder
        // Decorate-sort-undecorate: derive per-app sort keys once.
        let decorated = apps.filter(matchesFilter).map { app in
            (app: app,
             hasUpdate: sortOrder == .recommended ? store.update(for: app) != nil : false,
             summary: sortOrder == .source ? sourceSummary(for: app) : "")
        }
        return decorated.sorted { leftEntry, rightEntry in
            let left = leftEntry.app, right = rightEntry.app
            let comparison: ComparisonResult
            switch sortOrder {
            case .recommended:
                let leftHasUpdate = leftEntry.hasUpdate
                let rightHasUpdate = rightEntry.hasUpdate
                if leftHasUpdate != rightHasUpdate { return leftHasUpdate }
                comparison = left.name.localizedStandardCompare(right.name)
            case .name:
                comparison = left.name.localizedStandardCompare(right.name)
            case .source:
                comparison = leftEntry.summary.localizedStandardCompare(rightEntry.summary)
            case .installedVersion:
                comparison = VersionComparator.compare(left.installedVersion, right.installedVersion)
            case .availableVersion:
                comparison = VersionComparator.compare(
                    update(for: left)?.availableVersion ?? left.installedVersion,
                    update(for: right)?.availableVersion ?? right.installedVersion
                )
            case .installDate:
                comparison = ListSorting.compareDates(
                    left.installedAt, right.installedAt,
                    leftName: left.name, rightName: right.name
                )
            case .recentlyUpdated:
                comparison = ListSorting.compareDates(
                    left.modifiedAt, right.modifiedAt,
                    leftName: left.name, rightName: right.name
                )
            }
            return store.appSortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }.map(\.app)
    }

    private func matchesFilter(_ app: InstalledApp) -> Bool {
        switch store.appListFilter {
        case .all: true
        case .updates: update(for: app) != nil
        case .adoptable: store.adoptableApp(for: app) != nil
        case .appStore: app.updateManagement == .appStore
        case .testFlight: app.updateManagement == .testFlight
        case .setapp: app.updateManagement == .setapp
        case .microsoftAutoUpdate: app.updateManagement == .microsoftAutoUpdate
        case .homebrew: store.homebrewPackage(for: app) != nil
        case .sparkle: app.sparkleFeedURL != nil
        case .github: app.githubRepository != nil
        case .unmapped: isUnmapped(app)
        }
    }

    private func isUnmapped(_ app: InstalledApp) -> Bool {
        store.sources(for: app).isEmpty
            && !app.updateManagement.isExternallyManaged
            && !app.hasBuiltInUpdater
    }

    private var selectedAppID: Binding<String?> {
        Binding(
            get: {
                guard let selected = store.selectedApp, apps.contains(where: { $0.id == selected.id }) else { return nil }
                return selected.id
            },
            set: { identifier in
                store.selectedApp = identifier.flatMap { id in apps.first { $0.id == id } }
            }
        )
    }

    private func activeExclusion(
        for app: InstalledApp,
        update: AvailableUpdate?
    ) -> UpdateExclusion? {
        if let update,
           let exclusion = store.exclusion(for: app, version: update.availableVersion) { return exclusion }
        return store.ignoredExclusion(for: app)
    }

    private func update(for app: InstalledApp) -> AvailableUpdate? {
        store.update(for: app)
    }

    private func sourceSummary(for app: InstalledApp) -> String {
        let sources = store.sources(for: app)
        guard let first = sources.first else {
            if app.updateManagement.isExternallyManaged { return app.updateManagement.rawValue }
            return app.hasBuiltInUpdater ? "Built-in updater" : "No update source"
        }
        return sources.count == 1 ? first.rawValue : "\(first.rawValue) + \(sources.count - 1) more"
    }

}

struct AppDetailView: View {
    @UpkeepStoreReference private var store
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var inspection = AppSecurityInspectionModel()
    @StateObject private var detailState = AppDetailState()
    @UpkeepState private var showsFullReleaseNotes = false
    let app: InstalledApp

    private var update: AvailableUpdate? { store.update(for: app) }
    private var adoptableItem: AdoptableApp? { store.adoptableApp(for: app) }
    private var updateAdoptsWithHomebrew: Bool {
        guard let update, let adoptableItem else { return false }
        return update.source == .homebrew && update.primaryCandidate.requiresHomebrewAdoption && update.homebrewToken == adoptableItem.caskToken
    }
    private var adoptionHandledByUpdate: Bool { updateAdoptsWithHomebrew && exclusion == nil }
    private var exclusion: UpdateExclusion? {
        if let update, let exclusion = store.exclusion(for: app, version: update.availableVersion) { return exclusion }
        return store.ignoredExclusion(for: app)
    }

    var body: some View {
        InfoPanel {
            header
        } content: {
                    CVESecuritySummary(item: CVEInventoryItem(app))
                    if app.needsAppleSiliconMigration {
                        AppleSiliconMigrationWarning { detailState.showsAppleSiliconMigration = true }
                    }
                    updateStatus
                    RelatedInstallations(app: app)
                    releaseNotes
                    if settings.sidebarViewMode == .advanced {
                        DisclosureGroup("Update sources") {
                            updateSources.padding(.top, 10)
                        }
                        DisclosureGroup("Manage GitHub repository") {
                            githubSourceManagement.padding(.top, 10)
                        }
                    }
                    homebrewManagement
                    if settings.sidebarViewMode == .advanced {
                        technicalDisclosure
                    }
        }
        .frame(minHeight: 0)
        .onChange(of: app.id) { _, _ in showsFullReleaseNotes = false }
        .sheet(isPresented: $detailState.showsAppleSiliconMigration) {
            AppleSiliconMigrationView(app: app).environment(\.upkeepStoreReference, store)
        }
        .task(id: detailState.showsTechnicalDetails ? app.id : nil) {
            guard detailState.showsTechnicalDetails else { return }
            await inspection.load(app)
        }
        .task(id: app.id) {
            detailState.githubRepositoryEntry = settings.githubRepository(for: app.bundleIdentifier)
                ?? app.githubRepository
                ?? ""
        }
    }

    private var header: some View {
        InfoPanelHeader(title: app.name) {
            AppIcon(url: app.url, size: 44)
        } detail: {
                if store.isRunning(app) { RunningBadge() }
                if let update {
                    VersionTransitionView(
                        current: app.installedVersion,
                        latest: update.displayAvailableVersion,
                        usesFixedWidth: false
                    )
                } else {
                    Text("Version \(app.installedVersion)" + buildText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(store.sources(for: app)) { source in SourceBadge(source: source) }
                    if app.updateManagement.isExternallyManaged {
                        ManagementBadge(management: app.updateManagement)
                    }
                    if let channel = update?.prereleaseChannel ?? app.prereleaseChannel {
                        PrereleaseBadge(
                            channel: channel,
                            isInstalled: update?.prereleaseIsInstalled ?? (app.prereleaseChannel != nil)
                        )
                    }
                    if let exclusion {
                        Label(exclusion.mode.rawValue, systemImage: exclusion.mode == .ignored ? "eye.slash.fill" : "forward.end.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                ItemCheckStatus(
                    isRefreshing: store.isRefreshing(app),
                    lastChecked: store.lastChecked(for: app)
                )
            }
    }

    private var technicalDisclosure: some View {
        DisclosureGroup(isExpanded: $detailState.showsTechnicalDetails) {
            VStack(alignment: .leading, spacing: 20) {
                technicalDetails
                AppPermissionsSection(report: inspection.report)
                AppSecuritySection(report: inspection.report)
            }
            .padding(.top, 14)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label("Technical Details", systemImage: "info.circle")
                    .font(.headline)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var updateSources: some View {
        if let update, update.candidates.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Text("Update Sources").font(.headline)
                Text("Upkeep prefers the first source below, but every source that reported a newer version remains available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(Array(update.candidates.enumerated()), id: \.element.id) { index, candidate in
                        if index > 0 { Divider() }
                        HStack(spacing: 12) {
                            SourceBadge(source: candidate.source)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 7) {
                                    Text("Version \(update.selecting(candidate).displayAvailableVersion)")
                                        .font(.callout.weight(.medium))
                                        .monospacedDigit()
                                    if index == 0 {
                                        Text("PREFERRED")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if candidate.requiresHomebrewAdoption {
                                    Text("Using this source will move the app under Homebrew management.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if candidate.requiresInAppInstallation {
                                    Text(candidate.source == .sparkle
                                        ? "This update uses a package installer and must be started from the app."
                                        : "This update is installed by the app's built-in updater.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(candidate.verification.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if index > 0 {
                                Button(candidateActionTitle(candidate)) {
                                    Task { await store.performUpdate(update.selecting(candidate)) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(store.isUpdating(update.selecting(candidate)))
                            }
                        }
                        .padding(12)
                    }
                }
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @ViewBuilder
    private var githubSourceManagement: some View {
        if app.bundleIdentifier != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("GitHub Source").font(.headline)
                Text("Attach a publisher repository when Upkeep cannot discover one from the app. The repository must have published releases.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    TextField("owner/project", text: $detailState.githubRepositoryEntry)
                        .textFieldStyle(.roundedBorder)
                        .disabled(detailState.isSavingGitHubRepository)
                    Button(settings.githubRepository(for: app.bundleIdentifier) == nil ? "Verify & Use" : "Update") {
                        detailState.isSavingGitHubRepository = true
                        Task {
                            await store.setGitHubRepository(detailState.githubRepositoryEntry, for: app)
                            detailState.isSavingGitHubRepository = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        detailState.isSavingGitHubRepository
                            || GitHubClient.normalizedRepository(detailState.githubRepositoryEntry) == nil
                    )
                    if settings.githubRepository(for: app.bundleIdentifier) != nil {
                        Button("Remove") {
                            detailState.isSavingGitHubRepository = true
                            Task {
                                await store.removeCustomGitHubRepository(for: app)
                                detailState.githubRepositoryEntry = store.selectedApp?.githubRepository ?? ""
                                detailState.isSavingGitHubRepository = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(detailState.isSavingGitHubRepository)
                    }
                }
                if detailState.isSavingGitHubRepository {
                    ProgressView("Validating publisher releases…")
                        .controlSize(.small)
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var updateStatus: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: statusIcon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(statusColor)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 5) {
                    Text(statusTitle).font(.headline)
                    Text(primaryDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let detail = Self.additionalManagedDetail(
                        app.managedUpdateStatus?.detail,
                        primaryDescription: primaryDescription
                    ) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let verification = store.externalUpdateVerification(for: app) {
                        Text(verification.detail)
                            .font(.caption)
                            .foregroundStyle(
                                verification.state == .attention ? Color.orange : Color.secondary
                            )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                Spacer(minLength: 0)
                updateOptionsMenu
            }
            if let progress = app.managedUpdateStatus?.progress {
                ProgressView(value: progress)
                    .accessibilityLabel(app.managedUpdateStatus?.state.rawValue ?? "Update progress")
            }
            actionGrid
        }
        .upkeepOutlinedInspectorCard()
        .upkeepAnimated(for: statusTitle)
    }

    @ViewBuilder
    private var releaseNotes: some View {
        if let update {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("What’s New").font(.headline)
                    Spacer()
                    Text("Version \(update.displayAvailableVersion)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    let notes = update.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    Text(notes.isEmpty
                         ? AttributedString("No release notes available")
                         : ReleaseNotesFormatter.attributedString(from: notes))
                        .lineLimit(showsFullReleaseNotes ? nil : 10)
                        .font(.callout)
                        .lineSpacing(3)
                        .foregroundStyle(notes.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !notes.isEmpty {
                        Button(showsFullReleaseNotes ? "Show Less" : "Read All Release Notes") {
                            showsFullReleaseNotes.toggle()
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(16)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @ViewBuilder
    private var homebrewManagement: some View {
        if let adoptableItem, !adoptionHandledByUpdate, !homebrewAdoptionIgnored {
            VStack(alignment: .leading, spacing: 10) {
                Text("Homebrew").font(.headline)
                HStack(spacing: 16) {
                    Image(systemName: "shippingbox.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .frame(width: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Manage this app with Homebrew").font(.headline)
                        Text("Adopt the existing installation with the \(adoptableItem.caskToken) cask.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var technicalDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkspaceSectionLabel(title: "App information")
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow { detailLabel("Bundle ID"); Text(app.bundleIdentifier ?? "Not declared").textSelection(.enabled) }
                GridRow { detailLabel("Location"); Text(app.url.path).lineLimit(2).textSelection(.enabled) }
                GridRow { detailLabel("Installed version"); Text(app.installedVersion).monospacedDigit() }
                GridRow { detailLabel("App architecture"); Text(app.architecture.rawValue) }
                if let build = app.buildVersion { GridRow { detailLabel("Build"); Text(build).monospacedDigit() } }
                if let size = inspection.report?.fileSize { GridRow { detailLabel("Size on disk"); Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) } }
                if let minimum = inspection.report?.minimumSystemVersion { GridRow { detailLabel("Minimum macOS"); Text(minimum).monospacedDigit() } }
                if let installedAt = app.installedAt { GridRow { detailLabel("Installed"); Text(installedAt.formatted(date: .abbreviated, time: .shortened)) } }
                if let modifiedAt = app.modifiedAt { GridRow { detailLabel("Modified"); Text(modifiedAt.formatted(date: .abbreviated, time: .shortened)) } }
                if let architectures = inspection.report?.architectures, !architectures.isEmpty {
                    GridRow { detailLabel("Architectures"); Text(architectures.joined(separator: ", ")) }
                }
                GridRow {
                    detailLabel("Update sources")
                    Text(sourceNames)
                }
                if app.isWrappedIOSApp { GridRow { detailLabel("Platform"); Text("iPhone and iPad app") } }
                GridRow { detailLabel("Update management"); Text(app.updateManagement.rawValue) }
                GridRow { detailLabel("App Store receipt"); Text(app.hasAppStoreReceipt ? "Present" : "Not found") }
                if let feed = app.sparkleFeedURL { GridRow { detailLabel("Sparkle feed"); Link(feed.host() ?? feed.absoluteString, destination: feed) } }
                if let feed = app.electronUpdateFeedURL { GridRow { detailLabel("Update server"); Link(feed.host() ?? feed.absoluteString, destination: feed) } }
                if let repository = app.githubRepository,
                   let url = URL(string: "https://github.com/\(repository)") {
                    GridRow { detailLabel("GitHub"); Link(repository, destination: url) }
                }
                if let adoptableItem { GridRow { detailLabel("Homebrew cask"); Text(adoptableItem.caskToken).textSelection(.enabled) } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .upkeepOutlinedInspectorCard()
        }
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], alignment: .leading, spacing: 10) {
            if let exclusion {
                Button { store.restore(exclusion) } label: {
                    Label("Restore Updates", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else if let update {
                Button {
                    Task { await store.performUpdate(update) }
                } label: {
                    WorkingActionLabel(
                        isWorking: store.isUpdating(update),
                        idleTitle: primaryActionTitle,
                        phase: store.updatePhase(for: .applicationUpdate(update.id))
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isUpdating(update))
            }
            if let adoptableItem, !adoptionHandledByUpdate, !homebrewAdoptionIgnored {
                Button {
                    Task { await store.adopt(adoptableItem) }
                } label: {
                    WorkingActionLabel(
                        isWorking: store.isWorking(.homebrewAdoption(adoptableItem.id)),
                        idleTitle: "Adopt",
                        workingTitle: "Adopting…",
                        phase: store.updatePhase(for: .homebrewAdoption(adoptableItem.id))
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(store.isWorking(.homebrewAdoption(adoptableItem.id)))
                .help("Adopt with Homebrew using the \(adoptableItem.caskToken) cask")
            }
            if app.updateManagement.isExternallyManaged {
                Button { store.openUpdateManager(for: app) } label: {
                    Label(app.updateManagement.actionTitle, systemImage: app.updateManagement.systemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if update?.actionTitle != "Open App" {
                Button { NSWorkspace.shared.open(app.url) } label: {
                    Label("Open App", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([app.url]) } label: {
                Label("Show in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if let sourceURL, sourceURL.standardizedFileURL != app.url.standardizedFileURL {
                Button { NSWorkspace.shared.open(sourceURL) } label: {
                    Label(sourceActionTitle, systemImage: sourceActionSystemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.regular)
    }

    private var primaryActionTitle: String {
        update?.actionTitle ?? "Update"
    }

    @ViewBuilder
    private var updateOptionsMenu: some View {
        Menu { updateOptionCommands } label: {
            Image(systemName: "ellipsis.circle").font(.body).frame(width: 24, height: 24)
        }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Refresh, update, exclusion, and app options")
            .accessibilityLabel("App options")
    }

    @ViewBuilder
    private var updateOptionCommands: some View {
        if let update {
            Button(update.actionTitle) { Task { await store.performUpdate(update) } }
                .disabled(store.isUpdating(update))
        }
        Button("Refresh") { Task { await store.refresh(app) } }
            .disabled(store.isWorking(.applicationRefresh(app.id)))
        Divider()
        if let exclusion {
            Button("Restore Updates") { store.restore(exclusion) }
        } else if let update {
                UpdateExclusionOptions(
                    skipTitle: "Skip Version \(update.displayAvailableVersion)",
                    ignoreTitle: "Ignore Updates Indefinitely",
                    skip: { store.skip(update) },
                    ignore: { store.ignore(app) },
                    skipFor: { store.skip(update, duration: $0) },
                    ignoreFor: { store.ignore(app, duration: $0) }
                )
        }
        if hasHomebrewAdoptionOption {
            if homebrewAdoptionIgnored {
                Button("Restore Homebrew Adoption") { store.restoreHomebrewAdoption(app) }
            } else {
                Button("Ignore Homebrew Adoption") { store.ignoreHomebrewAdoption(app) }
            }
        }
        Divider()
        Button("Open") { NSWorkspace.shared.open(app.url) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
    }

    private var hasHomebrewAdoptionOption: Bool {
        adoptableItem != nil || update?.candidates.contains(where: \.requiresHomebrewAdoption) == true
    }

    private var homebrewAdoptionIgnored: Bool { store.isHomebrewAdoptionIgnored(app) }

    private func candidateActionTitle(_ candidate: UpdateCandidate) -> String {
        app.isUpkeep ? "Update…" : candidate.actionTitle
    }

    private var failedSources: [UpdateSource] {
        (store.scanState.failedAppSources[app.id] ?? []).sorted { $0.rawValue < $1.rawValue }
    }

    private var statusTitle: String {
        if let exclusion { return exclusion.mode == .ignored ? "Updates ignored" : "Version skipped" }
        if update == nil, !failedSources.isEmpty { return "Update check incomplete" }
        if update == nil, app.updateManagement.isExternallyManaged {
            if let status = app.managedUpdateStatus, status.state != .managed {
                return status.state.rawValue
            }
            return "Managed by \(app.updateManagement.rawValue)"
        }
        guard update == nil else { return "Update available" }
        // Only claim "Up to date" when a source actually answered for this app.
        if store.sources(for: app).isEmpty { return "No update source" }
        if store.lastChecked(for: app) == nil { return "Not checked yet" }
        return "Up to date"
    }

    private var primaryDescription: String {
        guard let update else { return statusDescription }
        return update.requiresInAppInstallation
            ? "Open \(app.name) to install this update."
            : "Available through \(update.source.rawValue)"
    }

    /// The managed-updater detail, unless it repeats the description above it. Most
    /// externally managed apps report their `updateExplanation` as both.
    static func additionalManagedDetail(_ detail: String?, primaryDescription: String) -> String? {
        guard let detail, detail != primaryDescription else { return nil }
        return detail
    }

    private var statusDescription: String {
        if let exclusion {
            return exclusion.mode == .ignored
                ? "Upkeep will not show updates for this app until you restore them."
                : "This version is skipped. A later release will appear automatically."
        }
        if !failedSources.isEmpty {
            let sources = failedSources.map(\.rawValue).joined(separator: ", ")
            return "\(sources) could not be checked. Upkeep cannot confirm this app is up to date. Review Source details or try Refresh again."
        }
        if app.updateManagement.isExternallyManaged { return app.updateManagement.updateExplanation }
        if store.source(for: app) == nil {
            return app.hasBuiltInUpdater
                ? "This app contains its own updater. Open the app to check or install updates."
                : "No supported update source was detected for this app."
        }
        return "No newer version was reported by the configured update source."
    }

    private var statusIcon: String {
        if let exclusion { return exclusion.mode == .ignored ? "eye.slash.circle.fill" : "forward.end.circle.fill" }
        if update == nil, !failedSources.isEmpty { return "exclamationmark.triangle.fill" }
        if update == nil, app.updateManagement.isExternallyManaged { return "gearshape.2.fill" }
        if update == nil, app.hasBuiltInUpdater { return "arrow.triangle.2.circlepath.circle.fill" }
        return update == nil ? "checkmark.circle.fill" : "arrow.down.circle.fill"
    }

    private var statusColor: Color {
        if exclusion != nil { return .orange }
        if update == nil, !failedSources.isEmpty { return .orange }
        if update == nil, app.updateManagement.isExternallyManaged { return .blue }
        if update == nil, app.hasBuiltInUpdater { return .blue }
        return update == nil ? .green : .accentColor
    }

    private var sourceURL: URL? {
        if let actionURL = update?.actionURL { return actionURL }
        switch update?.source ?? store.source(for: app) {
        case .homebrew:
            guard let token = store.homebrewPackage(for: app)?.token ?? adoptableItem?.caskToken ?? update?.homebrewToken else { return nil }
            return URL(string: "https://formulae.brew.sh/cask/\(token)")
        case .github:
            guard let repository = app.githubRepository else { return nil }
            return URL(string: "https://github.com/\(repository)")
        case .developer:
            return app.url
        case .sparkle:
            return app.sparkleFeedURL
        case .appStore:
            return URL(string: "macappstore://showUpdatesPage")
        case nil:
            return nil
        }
    }

    private var sourceActionTitle: String {
        switch update?.source ?? store.source(for: app) {
        case .appStore: "Open App Store"
        case .homebrew: "Open Homebrew"
        case .developer: sourceURL?.isFileURL == true ? "Open App" : "Open Update Page"
        case .github: update == nil ? "Open GitHub" : "Open Release"
        case .sparkle: update?.actionURL == nil ? "Open Sparkle" : "Open Download"
        case nil: "Open Source"
        }
    }

    private var sourceActionSystemImage: String {
        switch update?.source ?? store.source(for: app) {
        case .appStore: "storefront"
        case .homebrew: "shippingbox"
        case .developer: sourceURL?.isFileURL == true ? "arrow.triangle.2.circlepath" : "arrow.up.right.square"
        case .github: "arrow.up.right.square"
        case .sparkle: update?.requiresInAppInstallation == true ? "arrow.down.circle" : "wand.and.stars"
        case nil: "arrow.up.right.square"
        }
    }

    private var buildText: String { app.buildVersion.map { " (build \($0))" } ?? "" }
    private var sourceNames: String {
        let names = store.sources(for: app).map(\.rawValue).joined(separator: ", ")
        if !names.isEmpty { return names }
        if app.updateManagement.isExternallyManaged { return app.updateManagement.rawValue }
        return app.hasBuiltInUpdater ? "Built-in updater" : "No source"
    }
    private func detailLabel(_ text: String) -> some View { Text(text).foregroundStyle(.secondary) }
}

@MainActor
private final class AppDetailState: ObservableObject {
    @Published var showsAppleSiliconMigration = false
    @Published var showsTechnicalDetails = false
    @Published var githubRepositoryEntry = ""
    @Published var isSavingGitHubRepository = false
}


struct SourceBadge: View {
    let source: UpdateSource
    var body: some View {
        Text(source.rawValue).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(color).background(color.opacity(0.1), in: Capsule())
    }
    private var color: Color {
        switch source {
        case .appStore: .blue
        case .developer: .teal
        case .sparkle: .purple
        case .homebrew: .orange
        case .github: .primary
        }
    }
}

struct ManagementBadge: View {
    let management: AppUpdateManagement
    var body: some View {
        Text(management.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(.teal)
            .background(Color.teal.opacity(0.1), in: Capsule())
            .help(management.updateExplanation)
    }
}

struct RunningBadge: View {
    var body: some View {
        Label("Running", systemImage: "circle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.green)
            .labelStyle(.titleAndIcon)
            .help("This app is currently running")
            .accessibilityLabel("Running")
    }
}

/// Holds AllAppsView projections across body evaluations. Mutating it does
/// not invalidate the view; keys include every input the projection reads.
@MainActor
final class AllAppsProjection {
    struct Key: Equatable {
        let apps: [InstalledApp]
        let appGeneration: UInt64
        let updateGeneration: UInt64
        let homebrewGeneration: UInt64
        let adoptableGeneration: UInt64
        let filter: AppListFilter
        let sortOrder: AppSortOrder
        let ascending: Bool
    }

    private var cache = ListProjectionCache<InstalledApp, Key>()
    private var duplicates: (generation: UInt64, ids: Set<String>)?

    func values(for key: Key, build: () -> [InstalledApp]) -> [InstalledApp] {
        cache.values(for: key, build: build)
    }

    /// Bundle IDs shared by more than one installed app.
    func duplicateBundleIDs(in apps: [InstalledApp], generation: UInt64) -> Set<String> {
        if let duplicates, duplicates.generation == generation { return duplicates.ids }
        var seen = Set<String>(), shared = Set<String>()
        for bundleID in apps.compactMap(\.bundleIdentifier) where !seen.insert(bundleID).inserted {
            shared.insert(bundleID)
        }
        duplicates = (generation, shared)
        return shared
    }
}
