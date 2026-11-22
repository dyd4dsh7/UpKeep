import SwiftUI

struct SourceHealthView: View {
    @UpkeepStoreReference private var store
    @ObservedObject var settings: AppSettings
    @UpkeepState private var showingSuccessfulChecks = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Built once per render; row helpers look keys up instead of scanning inventory.
        let targets = SourceHealthTargets(store: store, keys: settings.sourceCheckFreshness.keys)
        let failures = settings.sourceCheckFreshness.values.count { $0.failure != nil }
        let successes = settings.sourceCheckFreshness.count - failures
        Section("Check Health") {
            if settings.sourceCheckFreshness.isEmpty {
                Label("Run an update check to see source health.", systemImage: "clock")
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    failures == 0
                        ? "No recorded check failures"
                        : WorkspaceSummary.count(failures, "source needs attention", "sources need attention"),
                    systemImage: failures == 0 ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .foregroundStyle(failures == 0 ? UpkeepPalette.accent(in: scheme) : UpkeepColors.warning(in: scheme))
                if successes > 0 {
                    Toggle("Show successful checks (\(successes.formatted()))", isOn: $showingSuccessfulChecks)
                }
            }
            ForEach(settings.sourceCheckFreshness.keys.filter {
                showingSuccessfulChecks || settings.sourceCheckFreshness[$0]?.failure != nil
            }.sorted(), id: \.self) { key in
                if let health = settings.sourceCheckFreshness[key] {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(title(for: key, targets), systemImage: health.failure == nil ? "checkmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(health.failure == nil ? Color.primary : UpkeepColors.warning(in: scheme))
                            Spacer()
                            if health.failure != nil, canRetry(key, targets) {
                                Button("Retry") { Task { await retry(key, targets) } }
                                    .disabled(isRetrying(key, targets))
                            }
                        }
                        Text("Attempted \(health.lastAttempt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let success = health.lastSuccess {
                            Text("Last successful check \(success.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        } else { Text("No successful check recorded").font(.caption).foregroundStyle(.secondary) }
                        if let failure = health.failure {
                            Text(failure).font(.callout).textSelection(.enabled)
                            if health.isRetained {
                                Text("Showing results from the previous successful check.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.vertical, 4)
                }
            }
        }
    }

    private func managerTarget(_ key: String) -> DeveloperPackageManager? {
        DeveloperPackageManager.allCases.first { key == "developer|\($0.rawValue)" }
    }

    private func title(for key: String, _ targets: SourceHealthTargets) -> String {
        if let package = targets.developerVersions[key] { return "\(package.name) · Available versions" }
        if let (app, source) = targets.apps[key] { return "\(app.name) · \(source.rawValue)" }
        if let manager = managerTarget(key) { return manager.rawValue }
        if let model = targets.models[key] { return "\(model.name) · \(model.runtime.rawValue)" }
        switch key {
        case "homebrew.inventory": return "Homebrew installed packages"
        case "homebrew.catalog": return "Homebrew app catalogue"
        case "macos.updates": return "macOS updates"
        case "macos.installers": return "macOS installers"
        default:
            if key.hasPrefix("app|"), let source = key.split(separator: "|").last {
                return "Previously checked app · \(source)"
            }
            if key.hasPrefix("model.runtime|") { return "AI models · \(key.dropFirst("model.runtime|".count))" }
            if key.hasPrefix("developer.versions|") { return "Previously checked package versions" }
            if key.hasPrefix("model|") { return "Previously checked model" }
            if key.hasPrefix("homebrew|"), let token = key.split(separator: "|").last { return "Homebrew · \(token)" }
            return "Previously checked source"
        }
    }

    private func runtimeTarget(_ key: String, _ targets: SourceHealthTargets) -> LocalModelRuntime? {
        if let model = targets.models[key] { return model.runtime }
        return LocalModelRuntime.allCases.first { key == "model.runtime|\($0.rawValue)" }
    }

    private func canRetry(_ key: String, _ targets: SourceHealthTargets) -> Bool {
        key == "macos.updates" || key == "macos.installers" || key == "homebrew.inventory" || key == "homebrew.catalog"
            || targets.apps[key] != nil || managerTarget(key) != nil || runtimeTarget(key, targets) != nil
            || targets.packages[key] != nil || targets.developerVersions[key] != nil
    }

    private func isRetrying(_ key: String, _ targets: SourceHealthTargets) -> Bool {
        if let package = targets.developerVersions[key] { return store.isWorking(.developerRefresh(package.id)) }
        if key == "macos.updates" || key == "macos.installers" { return store.isScanning || store.isWorking(.macOSSourceScan) }
        if key == "homebrew.catalog" { return store.isScanning || store.isWorking(.homebrewCatalogScan) }
        if key == "homebrew.inventory" { return store.isScanning || store.isWorking(.homebrewInventoryScan) }
        if let (app, _) = targets.apps[key] { return store.isRefreshing(app) }
        if let manager = managerTarget(key) { return store.isWorking(.developerScan(manager)) }
        if let runtime = runtimeTarget(key, targets) { return store.isWorking(.localModelRuntimeScan(runtime)) }
        if let package = targets.packages[key] { return store.isWorking(.homebrewRefresh(package.id)) }
        return false
    }

    private func retry(_ key: String, _ targets: SourceHealthTargets) async {
        if let package = targets.developerVersions[key] { await store.refresh(package); return }
        if key == "macos.updates" || key == "macos.installers" { await store.scanMacOSSource(key == "macos.updates" ? .updates : .installers) }
        else if key == "homebrew.catalog" { await store.scanHomebrewCatalog() }
        else if key == "homebrew.inventory" { await store.scanHomebrewInventory() }
        else if let (app, source) = targets.apps[key] { await store.refresh(app, sources: [source]) }
        else if let manager = managerTarget(key) { await store.scanDeveloperPackages(manager: manager) }
        else if let runtime = runtimeTarget(key, targets) { await store.scanLocalModels(runtime: runtime) }
        else if let package = targets.packages[key] { await store.refresh(package) }
    }
}

/// Source-health keys resolved to inventory items, keeping the first match
/// for a key as the previous linear searches did.
@MainActor
struct SourceHealthTargets {
    let apps: [String: (InstalledApp, UpdateSource)]
    let models: [String: LocalLLMModel]
    let packages: [String: HomebrewPackage]
    let developerVersions: [String: DeveloperPackage]

    init<Keys: Sequence<String>>(store: UpkeepStore, keys: Keys) {
        // App keys are "app|<app id>|<source>"; resolve only the recorded keys.
        var apps: [String: (InstalledApp, UpdateSource)] = [:]
        for key in keys where key.hasPrefix("app|") {
            let rest = key.dropFirst("app|".count)
            guard let separator = rest.lastIndex(of: "|"),
                  let source = UpdateSource(rawValue: String(rest[rest.index(after: separator)...])),
                  let app = store.app(forID: String(rest[..<separator])) else { continue }
            apps[key] = (app, source)
        }
        self.apps = apps
        models = Dictionary(store.localModels.map { ("model|\($0.id)", $0) }, uniquingKeysWith: { first, _ in first })
        packages = Dictionary(store.homebrewPackages.map { ("homebrew|\($0.kind.rawValue)|\($0.token)", $0) },
                              uniquingKeysWith: { first, _ in first })
        developerVersions = Dictionary(store.developerPackages.map { ("developer.versions|\($0.id)", $0) },
                                       uniquingKeysWith: { first, _ in first })
    }
}
