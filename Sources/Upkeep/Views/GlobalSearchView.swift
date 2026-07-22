import SwiftUI

struct GlobalSearchView: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        VStack(spacing: 0) {
            if resultCount == 0 {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("No apps, packages, models, system updates, or history match “\(displayQuery)”.")
                } actions: {
                    Button("Clear Search") { store.searchText = "" }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !matchingApps.isEmpty {
                        Section("Applications") {
                            ForEach(matchingApps) { app in appRow(app) }
                        }
                    }
                    if !matchingAdoptableApps.isEmpty {
                        Section("Adoptable Apps") {
                            ForEach(matchingAdoptableApps) { item in adoptableRow(item) }
                        }
                    }
                    if !matchingHomebrewPackages.isEmpty {
                        Section("Homebrew Packages") {
                            ForEach(matchingHomebrewPackages) { package in homebrewRow(package) }
                        }
                    }
                    if !matchingDeveloperPackages.isEmpty {
                        Section("Developer Packages") {
                            ForEach(matchingDeveloperPackages) { package in developerRow(package) }
                        }
                    }
                    if !matchingModels.isEmpty {
                        Section("AI Models") {
                            ForEach(matchingModels) { model in modelRow(model) }
                        }
                    }
                    if !matchingMacOSUpdates.isEmpty {
                        Section("macOS") {
                            ForEach(matchingMacOSUpdates) { update in macOSRow(update) }
                        }
                    }
                    if !matchingHistory.isEmpty {
                        Section("Update History") {
                            ForEach(matchingHistory) { record in historyRow(record) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var query: String {
        store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var displayQuery: String {
        store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingApps: [InstalledApp] {
        store.apps.filter { app in
            matches(app.name, app.bundleIdentifier, app.installedVersion, app.url.path,
                    app.updateManagement.rawValue, store.sources(for: app).map(\.rawValue).joined(separator: " "))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var matchingAdoptableApps: [AdoptableApp] {
        store.adoptableApps.filter { matches($0.app.name, $0.caskToken, $0.caskVersion) }
            .sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
    }

    private var matchingHomebrewPackages: [HomebrewPackage] {
        store.homebrewPackages.filter {
            matches($0.displayName, $0.token, $0.description, $0.kind.rawValue,
                    $0.installedVersion, $0.currentVersion, $0.dependencies.joined(separator: " "))
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var matchingDeveloperPackages: [DeveloperPackage] {
        store.developerPackages.filter {
            matches($0.name, $0.manager.rawValue, $0.currentVersion, $0.latestVersion, $0.executablePath)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var matchingModels: [LocalLLMModel] {
        store.localModels.filter {
            matches($0.name, $0.variant, $0.runtime.rawValue, $0.installedRevision, $0.latestRevision)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var matchingMacOSUpdates: [MacOSUpdate] {
        store.macOSUpdates.filter { matches($0.title, $0.label, $0.version, $0.size) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var matchingHistory: [UpdateRecord] {
        store.updateHistory.filter {
            matches($0.name, $0.kind.rawValue, $0.fromVersion, $0.toVersion, $0.recoveryNote)
        }.sorted { $0.date > $1.date }
    }

    private var resultCount: Int {
        matchingApps.count + matchingAdoptableApps.count + matchingHomebrewPackages.count
            + matchingDeveloperPackages.count + matchingModels.count + matchingMacOSUpdates.count
            + matchingHistory.count
    }

    private func matches(_ values: String?...) -> Bool {
        values.contains { $0?.lowercased().contains(query) == true }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        StandardItemRow {
            AppIcon(url: app.url, size: 36)
        } content: {
            ItemIdentityView(
                title: app.name,
                detail: appSourceSummary(app),
                isRunning: store.isRunning(app),
                prereleaseChannel: app.prereleaseChannel,
                prereleaseIsInstalled: app.prereleaseChannel != nil
            )
        } accessories: {
            InstalledVersionView(version: app.installedVersion)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.updateInspectorSelection = nil
            store.selectedApp = app
        }
    }

    private func adoptableRow(_ item: AdoptableApp) -> some View {
        StandardItemRow {
            AppIcon(url: item.app.url, size: 36)
        } content: {
            ItemIdentityView(title: item.app.name, detail: "Adoptable · Homebrew \(item.caskToken)")
        } accessories: {
            VersionTransitionView(current: item.app.installedVersion, latest: item.caskVersion)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.updateInspectorSelection = nil
            store.selectedApp = item.app
        }
    }

    private func homebrewRow(_ package: HomebrewPackage) -> some View {
        StandardItemRow {
            BundledPackageIcon(name: "homebrew", size: 36)
        } content: {
            ItemIdentityView(
                title: package.displayName,
                detail: "Homebrew \(package.kind.rawValue)" + (package.isDependency ? " · Dependency" : "")
            )
        } accessories: {
            VersionTransitionView(current: package.installedVersion, latest: package.isOutdated ? package.currentVersion : nil)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedApp = nil
            store.selectedPackageID = package.id
            store.updateInspectorSelection = .homebrew(package.id)
        }
    }

    private func developerRow(_ package: DeveloperPackage) -> some View {
        StandardItemRow {
            PackageManagerIcon(manager: package.manager)
        } content: {
            ItemIdentityView(title: package.name, detail: package.manager.rawValue)
        } accessories: {
            VersionTransitionView(current: package.currentVersion, latest: package.isOutdated ? package.latestVersion : nil)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedApp = nil
            store.selectedDeveloperPackageID = package.id
            store.updateInspectorSelection = .developer(package.id)
        }
    }

    private func modelRow(_ model: LocalLLMModel) -> some View {
        StandardItemRow {
            LocalModelRuntimeIcon(runtime: model.runtime, size: 36)
        } content: {
            ItemIdentityView(
                title: model.name,
                detail: model.variant.map { "\(model.runtime.rawValue) · \($0)" } ?? model.runtime.rawValue
            )
        } accessories: {
            VersionTransitionView(current: model.installedRevision, latest: model.isOutdated ? model.latestRevision : nil)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedApp = nil
            store.selectedLocalModelID = model.id
            store.updateInspectorSelection = .model(model.id)
        }
    }

    private func macOSRow(_ update: MacOSUpdate) -> some View {
        StandardItemRow {
            Image(systemName: update.isFullInstaller ? "internaldrive" : "apple.logo")
                .font(.title2).foregroundStyle(update.isBeta ? .purple : .blue)
        } content: {
            ItemIdentityView(
                title: update.title,
                detail: update.isFullInstaller ? "Full macOS installer" : "macOS system update",
                prereleaseChannel: update.prereleaseChannel
            )
        } accessories: {
            InstalledVersionView(version: update.version)
            Button("Open") { Task { await store.prepareMacOSUpdate(update) } }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private func historyRow(_ record: UpdateRecord) -> some View {
        StandardItemRow {
            Image(systemName: historyIcon(record.kind)).foregroundStyle(.blue)
        } content: {
            ItemIdentityView(
                title: record.name,
                detail: "\(record.kind.rawValue) · \(record.date.formatted(date: .abbreviated, time: .shortened))"
            )
        } accessories: {
            VersionTransitionView(current: record.fromVersion, latest: record.toVersion)
        }
    }

    private func appSourceSummary(_ app: InstalledApp) -> String {
        let sources = store.sources(for: app)
        if sources.isEmpty { return app.updateManagement.isExternallyManaged ? app.updateManagement.rawValue : "No update source" }
        return sources.map(\.rawValue).joined(separator: " · ")
    }

    private func historyIcon(_ kind: UpdateRecordKind) -> String {
        switch kind {
        case .app: "app.fill"
        case .homebrew: "shippingbox.fill"
        case .macOS: "apple.logo"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .model: "brain.head.profile.fill"
        }
    }
}
