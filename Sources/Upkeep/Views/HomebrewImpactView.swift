import SwiftUI

struct HomebrewImpactView: View {
    @UpkeepStoreReference private var store
    @ObservedObject var library: UpkeepLibraryState
    let package: HomebrewPackage
    let inventory: [HomebrewPackage]

    var body: some View {
        let impact = HomebrewImpact(package: package, inventory: inventory, services: library.homebrewServices)
        DisclosureGroup("Update impact") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Based on loaded installed packages. Homebrew resolves the final transaction when the update runs.")
                    .font(.caption).foregroundStyle(.secondary)
                if impact.dependencies.isEmpty {
                    Text("No installed dependencies found in this inventory.")
                } else {
                    Text("Installed dependencies: \(impact.dependencies.map(\.displayName).joined(separator: ", "))")
                }
                if !impact.outdatedDependencies.isEmpty {
                    Text("Dependencies with updates available: \(impact.outdatedDependencies.map(\.displayName).joined(separator: ", "))")
                }
                if !impact.dependents.isEmpty {
                    Text("Packages that depend on this: \(impact.dependents.map(\.displayName).joined(separator: ", "))")
                }
                if !impact.unresolvedDependencies.isEmpty {
                    Text("Not resolved in this inventory: \(impact.unresolvedDependencies.joined(separator: ", "))")
                        .foregroundStyle(.orange)
                }
                Divider()
                HStack {
                    Text("Homebrew services").font(.headline)
                    Spacer()
                    Button(library.isCheckingHomebrewServices ? "Checking…" : "Check services") {
                        Task { await store.scanHomebrewServices() }
                    }.disabled(library.isCheckingHomebrewServices)
                }
                Text("Services managed by Homebrew for the current user.")
                    .font(.caption).foregroundStyle(.secondary)
                if let failure = library.homebrewServicesFailure {
                    Text("Service check failed: \(failure)").foregroundStyle(.orange)
                    if library.homebrewServicesSucceededAt != nil {
                        Text("Showing results from the last successful check.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let checked = library.homebrewServicesSucceededAt {
                    Text("Last successful check: \(checked.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    if impact.relatedServices.isEmpty {
                        Text("No related services found in this inventory.")
                    }
                    ForEach(Array(impact.relatedServices.enumerated()), id: \.offset) { _, service in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(service.name): \(service.status)")
                            if service.isStarted {
                                Text("May need restarting after the update.").font(.caption).foregroundStyle(.secondary)
                            }
                            if let code = service.exitCode, code != 0 {
                                Text("Service exit code: \(code)").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    if !impact.unresolvedServiceNames.isEmpty {
                        Text("Service names not resolved in installed packages: \(impact.unresolvedServiceNames.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if !library.isCheckingHomebrewServices {
                    Text(library.homebrewServicesCheckedAt == nil
                        ? "Services have not been checked."
                        : "No successful service inventory is available.")
                        .foregroundStyle(.secondary)
                }
            }.font(.callout).padding(.top, 8).textSelection(.enabled)
        }
    }
}
