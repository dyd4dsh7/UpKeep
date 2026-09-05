import SwiftUI
import AppKit

/// Compare known installations without treating separate environments as redundant.
struct RelatedInstallations: View {
    @EnvironmentObject private var store: UpkeepStore
    var app: InstalledApp? = nil
    var package: DeveloperPackage? = nil

    private var copies: [(id: String, version: String, location: String, context: String)] {
        if let app, let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
            return store.apps.filter { $0.bundleIdentifier == bundleID }
                .map { (id: $0.id, version: $0.installedVersion, location: $0.url.path, context: $0.name) }
                .sorted { $0.location < $1.location }
        }
        if let package {
            return store.developerPackages.filter { $0.manager == package.manager && $0.name == package.name }
                .map { (id: $0.id, version: $0.currentVersion, location: $0.executablePath, context: $0.installationContext ?? $0.manager.rawValue) }
                .sorted { $0.location < $1.location }
        }
        return []
    }

    var body: some View {
        let installations = copies
        if installations.count > 1 {
            DisclosureGroup("Installations (\(installations.count))") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("These installations may belong to separate environments. Review each location before making changes.")
                        .font(.callout).foregroundStyle(.secondary)
                    if Set(installations.map(\.version)).count > 1 {
                        Label("Different versions installed", systemImage: "arrow.triangle.branch")
                            .font(.callout.weight(.medium))
                    }
                    ForEach(installations, id: \.id) { copy in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(copy.context).fontWeight(.medium)
                                Spacer()
                                Text(copy.version).monospacedDigit()
                            }
                            Text(copy.location)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            HStack {
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: copy.location)])
                                }
                                Spacer()
                                if copy.id == (app?.id ?? package?.id) {
                                    Label("Selected", systemImage: "checkmark")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("Inspect") { select(copy.id) }
                                }
                            }
                            .font(.caption)
                        }
                        .upkeepOutlinedInspectorCard()
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private func select(_ id: String) {
        if app != nil {
            store.selectedApp = store.apps.first { $0.id == id }
        } else if store.selection == .updates {
            store.updateInspectorSelection = .developer(id)
        } else {
            store.selectedDeveloperPackageID = id
        }
    }
}
