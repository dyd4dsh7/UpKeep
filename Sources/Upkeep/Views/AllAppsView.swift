import AppKit
import SwiftUI

struct AllAppsView: View {
    @EnvironmentObject private var store: UpkeepStore
    let apps: [InstalledApp]
    let title: String
    let systemImage: String

    var body: some View {
        let visibleApps = displayedApps
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
                            detail: sourceSummary(for: app),
                            isRunning: store.isRunning(app),
                            prereleaseChannel: update?.prereleaseChannel ?? app.prereleaseChannel,
                            prereleaseIsInstalled: update?.prereleaseIsInstalled ?? (app.prereleaseChannel != nil)
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
                .listStyle(.inset)
                .upkeepStateTransition()
            }
        }
        .upkeepAnimated(for: visibleApps.map(\.id))
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
            ListDensityButton()
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: emptySystemImage)
        } description: {
            Text(emptyDescription)
        } actions: {
            if store.searchText.isEmpty {
                Button("Check Again") { Task { await store.scan() } }
                    .buttonStyle(.borderedProminent)
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
        default: "No \(title) Apps"
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
        default: "No installed apps associated with \(title) were detected."
        }
    }

    private var emptySystemImage: String {
        if store.appListFilter == .unmapped { return "link.badge.plus" }
        return title == "No Source" ? "checkmark.seal" : systemImage
    }

    private var displayedApps: [InstalledApp] {
        apps.filter(matchesFilter).sorted { left, right in
            let comparison: ComparisonResult
            switch store.appSortOrder {
            case .recommended:
                let leftHasUpdate = store.update(for: left) != nil
                let rightHasUpdate = store.update(for: right) != nil
                if leftHasUpdate != rightHasUpdate { return leftHasUpdate }
                comparison = left.name.localizedStandardCompare(right.name)
            case .name:
                comparison = left.name.localizedStandardCompare(right.name)
            case .source:
                comparison = sourceSummary(for: left).localizedStandardCompare(sourceSummary(for: right))
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
        }
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
    @EnvironmentObject private var store: UpkeepStore
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var inspection = AppSecurityInspectionModel()
    @StateObject private var detailState = AppDetailState()
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
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    updateStatus
                    if settings.sidebarViewMode == .advanced {
                        updateSources
                        githubSourceManagement
                    }
                    releaseNotes
                    homebrewManagement
                    if settings.sidebarViewMode == .advanced {
                        technicalDisclosure
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 500)
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
        HStack(alignment: .top, spacing: 16) {
            AppIcon(url: app.url, size: 58)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    Text(app.name).font(.title.weight(.semibold)).lineLimit(2)
                    if store.isRunning(app) { RunningBadge() }
                }
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
            Spacer()
            Button { store.selectedApp = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close app details")
            .accessibilityLabel("Close app details")
            .keyboardShortcut(.cancelAction)
        }
        .padding(16)
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
                Text("Bundle metadata, declared permissions, signing, and Gatekeeper status")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var updateSources: some View {
        if let update, update.candidates.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Text("Update Sources").font(.title2.weight(.semibold))
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
                                    Text("This update uses a package installer and must be started from the app.")
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
                Text("GitHub Source").font(.title2.weight(.semibold))
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
            HStack(spacing: 16) {
                Image(systemName: statusIcon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(statusColor)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text(statusTitle).font(.title3.weight(.semibold))
                    if let update {
                        Text(update.requiresInAppInstallation
                             ? "Open \(app.name) to complete this Sparkle installer update."
                             : "Available through \(update.source.rawValue)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(statusDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let managedStatus = app.managedUpdateStatus {
                        Text(managedStatus.detail)
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
                Spacer()
                updateOptionsMenu
            }
            Divider()
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
                    Text("What’s New").font(.title2.weight(.semibold))
                    Spacer()
                    Text("Version \(update.displayAvailableVersion)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    let notes = update.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    Text(notes.isEmpty ? "No release notes available" : notes)
                        .font(.callout)
                        .lineSpacing(3)
                        .foregroundStyle(notes.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if notes.isEmpty {
                        Text("The developer did not provide release notes for this update source.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                Text("Homebrew").font(.title2.weight(.semibold))
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
            Text("Information").font(.title2.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 12) {
                GridRow { detailLabel("Bundle ID"); Text(app.bundleIdentifier ?? "Not declared").textSelection(.enabled) }
                GridRow { detailLabel("Location"); Text(app.url.path).lineLimit(2).textSelection(.enabled) }
                GridRow { detailLabel("Installed version"); Text(app.installedVersion).monospacedDigit() }
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
                GridRow { detailLabel("Update management"); Text(app.updateManagement.rawValue) }
                GridRow { detailLabel("App Store receipt"); Text(app.hasAppStoreReceipt ? "Present" : "Not found") }
                if let feed = app.sparkleFeedURL { GridRow { detailLabel("Sparkle feed"); Link(feed.host() ?? feed.absoluteString, destination: feed) } }
                if let repository = app.githubRepository,
                   let url = URL(string: "https://github.com/\(repository)") {
                    GridRow { detailLabel("GitHub"); Link(repository, destination: url) }
                }
                if let adoptableItem { GridRow { detailLabel("Homebrew cask"); Text(adoptableItem.caskToken).textSelection(.enabled) } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
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
                        idleTitle: primaryActionTitle
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
                        workingTitle: "Adopting…"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }

    private var primaryActionTitle: String {
        update?.actionTitle ?? "Update"
    }

    @ViewBuilder
    private var updateOptionsMenu: some View {
        Menu { updateOptionCommands } label: { Text("Options") }
            .menuStyle(.borderlessButton)
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
        app.isUpkeep ? "View Release" : candidate.actionTitle
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
        return update == nil ? "Up to date" : "Update available"
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
    @Published var showsTechnicalDetails = false
    @Published var githubRepositoryEntry = ""
    @Published var isSavingGitHubRepository = false
}

struct AppIcon: View {
    let url: URL
    let size: CGFloat
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().frame(width: size, height: size)
    }
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
