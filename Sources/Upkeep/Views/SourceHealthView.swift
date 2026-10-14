import SwiftUI

struct SourceHealthView: View {
    @UpkeepStoreReference private var store
    @ObservedObject var settings: AppSettings
    @State private var showingSuccessfulChecks = false

    var body: some View {
        Section("Check Health") {
            if settings.sourceCheckFreshness.isEmpty {
                Text("Run a check to see source health.").foregroundStyle(.secondary)
            } else {
                Toggle("Show successful checks", isOn: $showingSuccessfulChecks)
                if !settings.sourceCheckFreshness.values.contains(where: { $0.failure != nil }) {
                    Label("No recorded check failures", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
            }
            ForEach(settings.sourceCheckFreshness.keys.filter {
                showingSuccessfulChecks || settings.sourceCheckFreshness[$0]?.failure != nil
            }.sorted(), id: \.self) { key in
                if let health = settings.sourceCheckFreshness[key] {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(title(for: key), systemImage: health.failure == nil ? "checkmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(health.failure == nil ? Color.primary : Color.orange)
                            Spacer()
                            if health.failure != nil, canRetry(key) {
                                Button("Retry") { Task { await retry(key) } }
                                    .disabled(isRetrying(key))
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
                                Text("Previously known results are retained; refresh before relying on them.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.vertical, 4)
                }
            }
        }
    }

    private func appTarget(_ key: String) -> (InstalledApp, UpdateSource)? {
        for app in store.apps {
            for source in UpdateSource.allCases where key == "app|\(app.id)|\(source.rawValue)" {
                return (app, source)
            }
        }
        return nil
    }

    private func managerTarget(_ key: String) -> DeveloperPackageManager? {
        DeveloperPackageManager.allCases.first { key == "developer|\($0.rawValue)" }
    }

    private func title(for key: String) -> String {
        if let package = developerVersionTarget(key) { return "\(package.name) · Available versions" }
        if let (app, source) = appTarget(key) { return "\(app.name) · \(source.rawValue)" }
        if let manager = managerTarget(key) { return manager.rawValue }
        if let model = store.localModels.first(where: { key == "model|\($0.id)" }) { return "\(model.name) · \(model.runtime.rawValue)" }
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

    private func runtimeTarget(_ key: String) -> LocalModelRuntime? {
        if let model = store.localModels.first(where: { key == "model|\($0.id)" }) { return model.runtime }
        return LocalModelRuntime.allCases.first { key == "model.runtime|\($0.rawValue)" }
    }

    private func packageTarget(_ key: String) -> HomebrewPackage? {
        store.homebrewPackages.first { key == "homebrew|\($0.kind.rawValue)|\($0.token)" }
    }

    private func developerVersionTarget(_ key: String) -> DeveloperPackage? {
        store.developerPackages.first { key == "developer.versions|\($0.id)" }
    }

    private func canRetry(_ key: String) -> Bool { key == "macos.updates" || key == "macos.installers" || key == "homebrew.inventory" || key == "homebrew.catalog" || appTarget(key) != nil || managerTarget(key) != nil || runtimeTarget(key) != nil || packageTarget(key) != nil || developerVersionTarget(key) != nil }

    private func isRetrying(_ key: String) -> Bool {
        if let package = developerVersionTarget(key) { return store.isWorking(.developerRefresh(package.id)) }
        if key == "macos.updates" || key == "macos.installers" { return store.isScanning || store.isWorking(.macOSSourceScan) }
        if key == "homebrew.catalog" { return store.isScanning || store.isWorking(.homebrewCatalogScan) }
        if key == "homebrew.inventory" { return store.isScanning || store.isWorking(.homebrewInventoryScan) }
        if let (app, _) = appTarget(key) { return store.isRefreshing(app) }
        if let manager = managerTarget(key) { return store.isWorking(.developerScan(manager)) }
        if let runtime = runtimeTarget(key) { return store.isWorking(.localModelRuntimeScan(runtime)) }
        if let package = packageTarget(key) { return store.isWorking(.homebrewRefresh(package.id)) }
        return false
    }

    private func retry(_ key: String) async {
        if let package = developerVersionTarget(key) { await store.refresh(package); return }
        if key == "macos.updates" || key == "macos.installers" { await store.scanMacOSSource(key == "macos.updates" ? .updates : .installers) }
        else if key == "homebrew.catalog" { await store.scanHomebrewCatalog() }
        else if key == "homebrew.inventory" { await store.scanHomebrewInventory() }
        else if let (app, source) = appTarget(key) { await store.refresh(app, sources: [source]) }
        else if let manager = managerTarget(key) { await store.scanDeveloperPackages(manager: manager) }
        else if let runtime = runtimeTarget(key) { await store.scanLocalModels(runtime: runtime) }
        else if let package = packageTarget(key) { await store.refresh(package) }
    }
}
