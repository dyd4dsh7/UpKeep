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

            List(selection: selectedAppID) {
                ForEach(sortedApps) { app in
                StandardItemRow {
                    AppIcon(url: app.url, size: 36)
                } content: {
                    ItemIdentityView(
                        title: app.name,
                        detail: store.source(for: app)?.rawValue ?? "No update source",
                        isRunning: store.isRunning(app)
                    )
                } accessories: {
                    versions(for: app)
                }
                .tag(app.id)
                .contentShape(Rectangle())
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
            }
            .listStyle(.inset)
        }
    }

    private var sortedApps: [InstalledApp] {
        apps.sorted { left, right in
            let leftHasUpdate = store.updates.contains { $0.app.id == left.id }
            let rightHasUpdate = store.updates.contains { $0.app.id == right.id }
            if leftHasUpdate != rightHasUpdate { return leftHasUpdate }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private var selectedAppID: Binding<String?> {
        Binding(
            get: {
                guard let selected = store.selectedApp, apps.contains(where: { $0.id == selected.id }) else { return nil }
                return selected.id
            },
            set: { identifier in
                store.selectedApp = identifier.flatMap { id in apps.first { $0.id == id } }
            }
        )
    }

    private func activeExclusion(for app: InstalledApp) -> UpdateExclusion? {
        if let update = store.updates.first(where: { $0.app.id == app.id }),
           let exclusion = store.exclusion(for: app, version: update.availableVersion) { return exclusion }
        return store.ignoredExclusion(for: app)
    }

    @ViewBuilder
    private func versions(for app: InstalledApp) -> some View {
        if let exclusion = activeExclusion(for: app) {
            ItemStatusView(
                title: exclusion.mode.rawValue,
                systemImage: exclusion.mode == .ignored ? "eye.slash" : "forward.end",
                color: .orange
            )
            InstalledVersionView(version: app.installedVersion)
        } else if let update = store.visibleUpdates.first(where: { $0.app.id == app.id }) {
            VersionTransitionView(current: app.installedVersion, latest: update.availableVersion)
        } else {
            InstalledVersionView(version: app.installedVersion)
        }
    }
}

struct AppDetailView: View {
    @EnvironmentObject private var store: UpkeepStore
    let app: InstalledApp

    private var update: AvailableUpdate? { store.updates.first { $0.app.id == app.id } }
    private var adoptableItem: AdoptableApp? { store.adoptableApps.first { $0.app.id == app.id } }
    private var updateAdoptsWithHomebrew: Bool {
        guard let update, let adoptableItem else { return false }
        return update.source == .homebrew && update.homebrewToken == adoptableItem.caskToken
    }
    private var adoptionHandledByUpdate: Bool { updateAdoptsWithHomebrew && exclusion == nil }
    private var exclusion: UpdateExclusion? {
        if let update, let exclusion = store.exclusion(for: app, version: update.availableVersion) { return exclusion }
        return store.ignoredExclusion(for: app)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    updateStatus
                    releaseNotes
                    homebrewManagement
                    technicalDetails
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 500)
        .alert("The operation couldn’t be completed", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(store.errorMessage ?? "Unknown error") }
        .upkeepRunningAppConfirmationAlert(store)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            AppIcon(url: app.url, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    Text(app.name).font(.title.weight(.semibold)).lineLimit(2)
                    if store.isRunning(app) { RunningBadge() }
                }
                if let update {
                    VersionTransitionView(
                        current: app.installedVersion,
                        latest: update.availableVersion,
                        usesFixedWidth: false
                    )
                } else {
                    Text("Version \(app.installedVersion)" + buildText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let source = store.source(for: app) { SourceBadge(source: source) }
                    if let exclusion {
                        Label(exclusion.mode.rawValue, systemImage: exclusion.mode == .ignored ? "eye.slash.fill" : "forward.end.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Button { store.selectedApp = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close app details")
            .accessibilityLabel("Close app details")
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .background(.bar)
    }

    private var updateStatus: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: statusIcon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(statusColor)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text(statusTitle).font(.title3.weight(.semibold))
                    if let update {
                        Text("Available through \(update.source.rawValue)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(statusDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            Divider()
            actionGrid
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var releaseNotes: some View {
        if let update {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("What’s New").font(.title2.weight(.semibold))
                    Spacer()
                    Text("Version \(update.availableVersion)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    let notes = update.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    Text(notes.isEmpty ? "No release notes available" : notes)
                        .font(.callout)
                        .lineSpacing(3)
                        .foregroundStyle(notes.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if notes.isEmpty {
                        Text("The developer did not provide release notes for this update source.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @ViewBuilder
    private var homebrewManagement: some View {
        if let adoptableItem, !adoptionHandledByUpdate {
            VStack(alignment: .leading, spacing: 10) {
                Text("Homebrew").font(.title2.weight(.semibold))
                HStack(spacing: 16) {
                    Image(systemName: "shippingbox.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .frame(width: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Manage this app with Homebrew").font(.headline)
                        Text("Adopt the existing installation with the \(adoptableItem.caskToken) cask.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await store.adopt(adoptableItem) }
                    } label: {
                        if store.workingIDs.contains(adoptableItem.id) { ProgressView().controlSize(.small) }
                        else { Text("Adopt with Homebrew") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.workingIDs.contains(adoptableItem.id))
                }
                .padding(16)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var technicalDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Information").font(.title2.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 12) {
                GridRow { detailLabel("Bundle ID"); Text(app.bundleIdentifier ?? "Not declared").textSelection(.enabled) }
                GridRow { detailLabel("Location"); Text(app.url.path).lineLimit(2).textSelection(.enabled) }
                GridRow { detailLabel("Installed version"); Text(app.installedVersion).monospacedDigit() }
                if let build = app.buildVersion { GridRow { detailLabel("Build"); Text(build).monospacedDigit() } }
                GridRow { detailLabel("Update source"); Text(store.source(for: app)?.rawValue ?? "No source") }
                GridRow { detailLabel("App Store receipt"); Text(app.hasAppStoreReceipt ? "Present" : "Not found") }
                if let feed = app.sparkleFeedURL { GridRow { detailLabel("Sparkle feed"); Link(feed.host() ?? feed.absoluteString, destination: feed) } }
                if let repository = app.githubRepository,
                   let url = URL(string: "https://github.com/\(repository)") {
                    GridRow { detailLabel("GitHub"); Link(repository, destination: url) }
                }
                if let adoptableItem { GridRow { detailLabel("Homebrew cask"); Text(adoptableItem.caskToken).textSelection(.enabled) } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], alignment: .leading, spacing: 10) {
            if let exclusion {
                Button { store.restore(exclusion) } label: {
                    Label("Restore Updates", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else if let update {
                Button {
                    Task { await store.performUpdate(update) }
                } label: {
                    if store.workingIDs.contains(update.id) {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    } else {
                        Label(primaryActionTitle, systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.workingIDs.contains(update.id))
            }
            Button { NSWorkspace.shared.open(app.url) } label: {
                Label("Open App", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button { NSWorkspace.shared.activateFileViewerSelecting([app.url]) } label: {
                Label("Show in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if let sourceURL {
                Button { NSWorkspace.shared.open(sourceURL) } label: {
                    Label(sourceActionTitle, systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if let update, exclusion == nil {
                Button { store.skip(update) } label: {
                    Label("Skip \(update.availableVersion)", systemImage: "forward.end")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if exclusion == nil {
                Button { store.ignore(app) } label: {
                    Label("Ignore Updates", systemImage: "eye.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }

    private var primaryActionTitle: String {
        guard let update else { return "Update" }
        if updateAdoptsWithHomebrew { return "Update & Adopt" }
        return switch update.source {
        case .homebrew: "Update"
        case .appStore: "Open App Store"
        case .sparkle: "Download"
        case .github: "View Release"
        }
    }

    private var statusTitle: String {
        if let exclusion { return exclusion.mode == .ignored ? "Updates ignored" : "Version skipped" }
        return update == nil ? "Up to date" : "Update available"
    }

    private var statusDescription: String {
        if let exclusion {
            return exclusion.mode == .ignored
                ? "Upkeep will not show updates for this app until you restore them."
                : "This version is skipped. A later release will appear automatically."
        }
        if store.source(for: app) == nil { return "No supported update source was detected for this app." }
        return "No newer version was reported by the configured update source."
    }

    private var statusIcon: String {
        if let exclusion { return exclusion.mode == .ignored ? "eye.slash.circle.fill" : "forward.end.circle.fill" }
        return update == nil ? "checkmark.circle.fill" : "arrow.down.circle.fill"
    }

    private var statusColor: Color {
        if exclusion != nil { return .orange }
        return update == nil ? .green : .accentColor
    }

    private var sourceURL: URL? {
        if let actionURL = update?.actionURL { return actionURL }
        switch update?.source ?? store.source(for: app) {
        case .homebrew:
            guard let token = store.homebrewPackage(for: app)?.token ?? adoptableItem?.caskToken ?? update?.homebrewToken else { return nil }
            return URL(string: "https://formulae.brew.sh/cask/\(token)")
        case .github:
            guard let repository = app.githubRepository else { return nil }
            return URL(string: "https://github.com/\(repository)")
        case .sparkle:
            return app.sparkleFeedURL
        case .appStore:
            return URL(string: "macappstore://showUpdatesPage")
        case nil:
            return nil
        }
    }

    private var sourceActionTitle: String {
        switch update?.source ?? store.source(for: app) {
        case .appStore: "Open App Store"
        case .homebrew: "Open Homebrew"
        case .github: update == nil ? "Open GitHub" : "Open Release"
        case .sparkle: update?.actionURL == nil ? "Open Sparkle" : "Open Download"
        case nil: "Open Source"
        }
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

struct RunningBadge: View {
    var body: some View {
        Label("Running", systemImage: "circle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.green)
            .labelStyle(.titleAndIcon)
            .help("This app is currently running")
            .accessibilityLabel("Running")
    }
}
