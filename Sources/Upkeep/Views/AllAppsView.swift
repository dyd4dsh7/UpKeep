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
                StandardItemRow {
                    AppIcon(url: app.url, size: 36)
                } content: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).fontWeight(.semibold).lineLimit(1)
                        Text(app.bundleIdentifier ?? app.url.path)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                } accessories: {
                    status(for: app)
                        .frame(width: 128, alignment: .trailing)
                    Text(app.installedVersion)
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .trailing)
                    Menu {
                        Button("View Details") { store.selectedApp = app }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                        Divider()
                        if let exclusion = activeExclusion(for: app) {
                            Button("Restore Updates") { store.restore(exclusion) }
                        } else {
                            if let update = store.updates.first(where: { $0.app.id == app.id }) {
                                Button("Skip Version \(update.availableVersion)") { store.skip(update) }
                            }
                            Button("Ignore \(app.name)") { store.ignore(app) }
                        }
                    } label: { MoreMenuIcon() }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                }
                .contentShape(Rectangle())
                .onTapGesture { store.selectedApp = app }
                .contextMenu {
                    Button("View Details") { store.selectedApp = app }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                    Divider()
                    if let exclusion = activeExclusion(for: app) {
                        Button("Restore Updates") { store.restore(exclusion) }
                    } else {
                        if let update = store.updates.first(where: { $0.app.id == app.id }) {
                            Button("Skip Version \(update.availableVersion)") { store.skip(update) }
                        }
                        Button("Ignore \(app.name)") { store.ignore(app) }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func activeExclusion(for app: InstalledApp) -> UpdateExclusion? {
        if let update = store.updates.first(where: { $0.app.id == app.id }),
           let exclusion = store.exclusion(for: app, version: update.availableVersion) { return exclusion }
        return store.ignoredExclusion(for: app)
    }

    @ViewBuilder
    private func status(for app: InstalledApp) -> some View {
        if let exclusion = activeExclusion(for: app) {
            Label(exclusion.mode.rawValue, systemImage: exclusion.mode == .ignored ? "eye.slash" : "forward.end")
                .font(.caption.weight(.medium)).foregroundStyle(.orange)
        } else if let update = store.visibleUpdates.first(where: { $0.app.id == app.id }) {
            Label("\(update.availableVersion) available", systemImage: "arrow.down.circle.fill")
                .font(.caption.weight(.medium)).foregroundStyle(.tint)
        } else {
            Label("Current", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AppDetailView: View {
    @EnvironmentObject private var store: UpkeepStore
    @Environment(\.dismiss) private var dismiss
    let app: InstalledApp

    private var update: AvailableUpdate? { store.updates.first { $0.app.id == app.id } }
    private var exclusion: UpdateExclusion? {
        if let update, let exclusion = store.exclusion(for: app, version: update.availableVersion) { return exclusion }
        return store.ignoredExclusion(for: app)
    }

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
                                if let exclusion {
                                    Label(exclusion.mode.rawValue, systemImage: exclusion.mode == .ignored ? "eye.slash" : "forward.end")
                                        .foregroundStyle(.orange)
                                    Button("Restore") { store.restore(exclusion) }
                                } else {
                                    Button("Update") { Task { await store.performUpdate(update) } }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(store.workingIDs.contains(update.id))
                                    Menu("More") {
                                        Button("Skip Version \(update.availableVersion)") { store.skip(update) }
                                        Button("Ignore \(app.name)") { store.ignore(app) }
                                    }
                                }
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
                        if update == nil {
                            if let exclusion {
                                Button("Restore Updates") { store.restore(exclusion) }
                            } else {
                                Button("Ignore Updates") { store.ignore(app) }
                            }
                        }
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
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2.weight(.medium))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
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
