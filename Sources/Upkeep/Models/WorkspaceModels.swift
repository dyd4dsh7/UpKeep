import Foundation

enum HomebrewFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case updates = "Updates"
    case requested = "Requested"
    case dependencies = "Dependencies"
    case casks = "Casks"
    case unmapped = "Unmapped"
    var id: Self { self }
    var requiresAdvancedView: Bool { self == .dependencies }
}

enum AppListFilter: String, CaseIterable, Identifiable {
    case all = "All Apps"
    case updates = "Updates"
    case adoptable = "Homebrew Suggestions"
    case appStore = "App Store"
    case testFlight = "TestFlight"
    case setapp = "Setapp"
    case microsoftAutoUpdate = "Microsoft AutoUpdate"
    case homebrew = "Homebrew"
    case sparkle = "Sparkle"
    case github = "GitHub"
    case unmapped = "Unmapped"
    var id: Self { self }
}

enum AppSortOrder: String, CaseIterable, Identifiable {
    case recommended = "Recommended"
    case name = "Name"
    case source = "Update Source"
    case installedVersion = "Installed Version"
    case availableVersion = "Available Version"
    case installDate = "Install Date"
    case recentlyUpdated = "Recently Updated"
    var id: Self { self }
}

enum HomebrewSortOrder: String, CaseIterable, Identifiable {
    case recommended = "Recommended"
    case name = "Name"
    case installedVersion = "Installed Version"
    case availableVersion = "Available Version"
    case kind = "Package Type"
    var id: Self { self }
}

enum UpdateListFilter: String, CaseIterable, Identifiable {
    case all = "All Updates"
    case applications = "Applications"
    case homebrew = "Homebrew"
    case macOS = "macOS"
    case developer = "Developer"
    case models = "AI Models"
    var id: Self { self }
}

enum UpdateSortOrder: String, CaseIterable, Identifiable {
    case recommended = "Recommended"
    case name = "Name"
    case source = "Source"
    case installedVersion = "Installed Version"
    case availableVersion = "Available Version"
    case installDate = "Install Date"
    case recentlyUpdated = "Recently Updated"
    var id: Self { self }
}

enum DeveloperManagerFilter: Hashable {
    case all
    case javaScript
    case manager(DeveloperPackageManager)

    var title: String {
        switch self {
        case .all: "All"
        case .javaScript: "JavaScript"
        case let .manager(manager): manager.rawValue
        }
    }

    func includes(_ manager: DeveloperPackageManager) -> Bool {
        switch self {
        case .all: true
        case .javaScript: manager.belongsToJavaScriptEcosystem
        case let .manager(selected): manager == selected
        }
    }

    func isAvailable(in managers: [DeveloperPackageManager]) -> Bool {
        switch self {
        case .all: true
        case .javaScript: managers.contains(where: \.belongsToJavaScriptEcosystem)
        case let .manager(manager): managers.contains(manager)
        }
    }
}

enum UpdateInspectorSelection: Equatable {
    case homebrew(String)
    case developer(String)
    case model(String)

    var listID: String {
        switch self {
        case let .homebrew(id): "homebrew:\(id)"
        case let .developer(id): "developer:\(id)"
        case let .model(id): "model:\(id)"
        }
    }
}
