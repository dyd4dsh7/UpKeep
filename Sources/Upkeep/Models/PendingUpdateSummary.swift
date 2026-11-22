import Foundation

/// An item on the Updates page that another surface (menu bar, notification) can reveal.
enum PendingUpdateTarget: Hashable, Sendable {
    case application(String)
    case homebrew(String)
    case developer(String)
    case model(String)
    case macOS(String)
}

struct PendingUpdateSummary: Identifiable, Hashable, Sendable {
    let target: PendingUpdateTarget
    let name: String
    let currentVersion: String?
    let availableVersion: String
    var id: PendingUpdateTarget { target }

    var versionText: String {
        guard let currentVersion, currentVersion != availableVersion else { return availableVersion }
        return "\(currentVersion) → \(availableVersion)"
    }
}

@MainActor
extension UpkeepStore {
    /// Every update counted by `totalUpdateCount`, in Updates-page section order.
    var pendingUpdateSummaries: [PendingUpdateSummary] {
        let plan = updatePlan
        func byName(_ left: PendingUpdateSummary, _ right: PendingUpdateSummary) -> Bool {
            left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
        let applications = plan.applicationUpdates.map {
            PendingUpdateSummary(target: .application($0.app.id), name: $0.app.name,
                currentVersion: $0.app.installedVersion, availableVersion: $0.displayAvailableVersion)
        }.sorted(by: byName)
        let homebrew = plan.unrepresentedHomebrewUpdates.map {
            PendingUpdateSummary(target: .homebrew($0.id), name: $0.displayName,
                currentVersion: $0.installedVersion, availableVersion: $0.currentVersion)
        }.sorted(by: byName)
        let system = macOSUpdates.filter { !$0.isFullInstaller }.map {
            PendingUpdateSummary(target: .macOS($0.id), name: $0.title, currentVersion: nil, availableVersion: $0.version)
        }.sorted(by: byName)
        // Matches the count: includes developer updates that open their manager.
        let developer = developerPackages.filter { $0.isOutdated && !isExcluded($0) }.map {
            PendingUpdateSummary(target: .developer($0.id), name: $0.name,
                currentVersion: $0.currentVersion, availableVersion: $0.latestVersion)
        }.sorted(by: byName)
        let models = plan.modelUpdates.map {
            PendingUpdateSummary(target: .model($0.id), name: $0.name,
                currentVersion: $0.installedRevision, availableVersion: $0.latestRevision)
        }.sorted(by: byName)
        return applications + homebrew + system + developer + models
    }

    /// Shows the Updates page in the main window, reopening it if needed.
    func showUpdates() {
        navigation.searchText = ""
        navigation.selection = .updates
        openMainWindow()
    }

    /// Opens the batch review sheet on the Updates page.
    func showBatchReview() {
        showUpdates()
        guard !availableBatchUpdateItems.isEmpty, !isWorking(.unifiedBatch) else { return }
        navigation.isShowingBatchReview = true
    }

    func revealPendingUpdate(_ target: PendingUpdateTarget) {
        navigation.searchText = ""
        if case let .macOS(id) = target {
            revealInventoryResult(.macOS(id))
            openMainWindow()
            return
        }
        if navigation.selection != .updates {
            // A live window clears the inspector after a destination change;
            // `completePendingUpdateReveal()` re-applies the selection then.
            navigation.pendingUpdateReveal = target
            navigation.selection = .updates
        }
        applyUpdateSelection(target)
        openMainWindow()
    }

    /// Called after a destination change has cleared the previous selection.
    func completePendingUpdateReveal() {
        guard let target = navigation.pendingUpdateReveal else { return }
        navigation.pendingUpdateReveal = nil
        if navigation.selection == .updates { applyUpdateSelection(target) }
    }

    private func applyUpdateSelection(_ target: PendingUpdateTarget) {
        switch target {
        case let .application(id):
            updateInspectorSelection = nil
            selectedApp = app(forID: id) ?? updates.first { $0.app.id == id }?.app
        case let .homebrew(id):
            selectedApp = nil
            selectedPackageID = id
            updateInspectorSelection = .homebrew(id)
        case let .developer(id):
            selectedApp = nil
            selectedDeveloperPackageID = id
            updateInspectorSelection = .developer(id)
            if let package = developerPackage(forID: id) {
                selectedDeveloperVersion = package.latestVersion
                Task { await loadAvailableVersions(for: package) }
            }
        case let .model(id):
            selectedApp = nil
            selectedLocalModelID = id
            updateInspectorSelection = .model(id)
        case .macOS:
            break
        }
    }
}
