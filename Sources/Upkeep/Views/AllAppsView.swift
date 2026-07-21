import AppKit
import SwiftUI

struct AllAppsView: View {
    @EnvironmentObject private var store: UpkeepStore
    let apps: [InstalledApp]
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(title: title, subtitle: subtitle, systemImage: "square.grid.2x2.fill")

            List(apps) { app in
                Button { store.selectedApp = app } label: {
                    HStack(spacing: 12) {
                        AppIcon(url: app.url, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).fontWeight(.medium)
                            Text(app.bundleIdentifier ?? app.url.path)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let update = store.updates.first(where: { $0.app.id == app.id }) {
                            Text("Update \(update.availableVersion)")
                                .font(.caption.weight(.medium)).foregroundStyle(.blue)
                        } else {
                            Label("No update found", systemImage: "checkmark")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(app.installedVersion)
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("View Details") { store.selectedApp = app }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                }
            }
            .listStyle(.inset)
        }
    }
}

struct AppDetailView: View {
    @EnvironmentObject private var store: UpkeepStore
    @Environment(\.dismiss) private var dismiss
    let app: InstalledApp

    private var update: AvailableUpdate? { store.updates.first { $0.app.id == app.id } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                AppIcon(url: app.url, size: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(app.name).font(.largeTitle.bold())
                    Text("Version \(app.installedVersion)" + buildText)
                        .font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                    if let source = store.source(for: app) { SourceBadge(source: source) }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(24)

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let update {
                        GroupBox("Available Update") {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(update.availableVersion).font(.title2.bold()).foregroundStyle(.blue)
                                    Text("Available through \(update.source.rawValue)").foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Update") { Task { await store.performUpdate(update) } }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(store.workingIDs.contains(update.id))
                            }.padding(8)
                        }
                    }

                    Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 12) {
                        GridRow { detailLabel("Bundle ID"); Text(app.bundleIdentifier ?? "Not declared").textSelection(.enabled) }
                        GridRow { detailLabel("Location"); Text(app.url.path).lineLimit(2).textSelection(.enabled) }
                        GridRow { detailLabel("Installed version"); Text(app.installedVersion).monospacedDigit() }
                        if let build = app.buildVersion { GridRow { detailLabel("Build"); Text(build).monospacedDigit() } }
                        GridRow { detailLabel("App Store receipt"); Text(app.hasAppStoreReceipt ? "Present" : "Not found") }
                        if let feed = app.sparkleFeedURL { GridRow { detailLabel("Sparkle feed"); Link(feed.host() ?? feed.absoluteString, destination: feed) } }
                        if let repository = app.githubRepository,
                           let url = URL(string: "https://github.com/\(repository)") {
                            GridRow { detailLabel("GitHub"); Link(repository, destination: url) }
                        }
                    }

                    HStack {
                        Button("Open App") { NSWorkspace.shared.open(app.url) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                    }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 620, minHeight: 470)
    }

    private var buildText: String { app.buildVersion.map { " (build \($0))" } ?? "" }
    private func detailLabel(_ text: String) -> some View { Text(text).foregroundStyle(.secondary) }
}

struct HeaderView: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage).font(.system(size: 30)).foregroundStyle(.blue).symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 20).background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
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
        switch source { case .appStore: .blue; case .sparkle: .purple; case .homebrew: .orange; case .github: .primary }
    }
}
