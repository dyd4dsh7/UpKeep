import Foundation

enum UpdateRiskGroup: Int, CaseIterable, Hashable, Identifiable, Sendable {
    case automatic
    case manual
    case major
    case prerelease
    case dependency
    case developer

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Recommended"
        case .manual: "Needs Your Attention"
        case .major: "Major Version Changes"
        case .prerelease: "Prereleases"
        case .dependency: "Dependencies"
        case .developer: "Developer Environment"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "Stable updates Upkeep can complete directly."
        case .manual: "Opens another app or changes how an item is managed."
        case .major: "May contain breaking or incompatible changes."
        case .prerelease: "Alpha, beta, preview, or other non-stable software."
        case .dependency: "Usually updated automatically with the packages that require them."
        case .developer: "Changes global tools and may affect existing projects."
        }
    }

    var systemImage: String {
        switch self {
        case .automatic: "checkmark.shield.fill"
        case .manual: "hand.raised.fill"
        case .major: "arrow.up.forward.circle.fill"
        case .prerelease: "testtube.2"
        case .dependency: "shippingbox.fill"
        case .developer: "terminal.fill"
        }
    }
}

extension BatchUpdateItem {
    var riskGroup: UpdateRiskGroup {
        if VersionComparator.isPrerelease(availableVersion) { return .prerelease }
        if case .developer = self { return .developer }
        if case let .homebrew(package) = self, package.isDependency { return .dependency }
        if UpdatePlan.isMajorVersionChange(from: currentVersion, to: availableVersion) { return .major }

        switch self {
        case let .application(update):
            if update.opensExternalUpdater || update.primaryCandidate.requiresHomebrewAdoption {
                return .manual
            }
            return .automatic
        case .homebrew:
            return .automatic
        case .developer:
            return .developer
        case .model:
            return .manual
        }
    }

    var isRecommendedByDefault: Bool { riskGroup == .automatic }
}

struct UpdatePlan: Sendable {
    let applicationUpdates: [AvailableUpdate]
    let homebrewUpdates: [HomebrewPackage]
    let macOSUpdates: [MacOSUpdate]
    let developerUpdates: [DeveloperPackage]
    let modelUpdates: [LocalLLMModel]

    var batchItems: [BatchUpdateItem] {
        let representedCaskTokens = Set(applicationUpdates.flatMap { $0.candidates.compactMap(\.homebrewToken) })
        let unrepresentedHomebrew = homebrewUpdates.filter { !representedCaskTokens.contains($0.token) }
        return applicationUpdates.map(BatchUpdateItem.application)
            + unrepresentedHomebrew.map(BatchUpdateItem.homebrew)
            + developerUpdates.map(BatchUpdateItem.developer)
            + modelUpdates.map(BatchUpdateItem.model)
    }

    var recommendedBatchItems: [BatchUpdateItem] {
        batchItems.filter(\.isRecommendedByDefault)
    }

    var primaryUpdateCount: Int {
        let representedCaskTokens = Set(applicationUpdates.flatMap { $0.candidates.compactMap(\.homebrewToken) })
        let requestedHomebrewCount = homebrewUpdates.count {
            !$0.isDependency && !representedCaskTokens.contains($0.token)
        }
        return applicationUpdates.count
            + requestedHomebrewCount
            + macOSUpdates.count(where: { !$0.isFullInstaller })
    }

    static func isMajorVersionChange(from current: String, to available: String) -> Bool {
        guard let currentMajor = firstNumericComponent(in: current),
              let availableMajor = firstNumericComponent(in: available) else { return false }
        return availableMajor > currentMajor
    }

    private static func firstNumericComponent(in version: String) -> UInt64? {
        let digits = version.drop(while: { !$0.isNumber }).prefix(while: \.isNumber)
        return UInt64(digits)
    }
}

private extension AvailableUpdate {
    var opensExternalUpdater: Bool { homebrewToken == nil && !canInstallDirectly }
}
