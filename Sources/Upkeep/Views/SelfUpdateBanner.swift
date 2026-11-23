import SwiftUI

/// Shown above the content when a newer Upkeep is available.
struct SelfUpdateBanner: View {
    @ObservedObject private var controller = SelfUpdateController.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let release = controller.bannerRelease {
            HStack(spacing: 12) {
                AppBrandIcon(size: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.isInstalling ? "Installing Upkeep \(release.version)…" : "Upkeep \(release.version) is available")
                        .font(.callout.weight(.semibold))
                    Text(controller.isInstalling
                         ? "Upkeep will quit and reopen when the update is verified."
                         : "You have version \(SelfUpdate.currentVersion).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if controller.isInstalling {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Release Notes") { controller.openReleasePage() }
                        .buttonStyle(.borderless)
                    Button("Later") { controller.dismiss() }
                        .buttonStyle(.bordered)
                    Button(release.canInstallInPlace ? "Update Now" : "Download…") {
                        if release.canInstallInPlace { Task { await controller.install() } } else { controller.openReleasePage() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, UpkeepLayout.pageInset)
            .padding(.vertical, 10)
            .background(UpkeepPalette.accent(in: scheme).opacity(0.10))
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Upkeep \(release.version) is available")
        }
    }
}

/// Settings › About: installed version, update status, and the check action.
struct SelfUpdateStatusRow: View {
    @ObservedObject private var controller = SelfUpdateController.shared

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let release = controller.availableRelease, !controller.isInstalling {
                Button(release.canInstallInPlace ? "Update to \(release.version)" : "Download \(release.version)…") {
                    if release.canInstallInPlace { Task { await controller.install() } } else { controller.openReleasePage() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Check Now") { Task { await controller.check(userInitiated: true) } }
                    .disabled(controller.phase == .checking || controller.isInstalling)
            }
        }
        .padding(14)
        .upkeepSurface()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var statusIcon: some View {
        switch controller.phase {
        case .checking, .installing:
            ProgressView().controlSize(.small)
        default:
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var title: String {
        switch controller.phase {
        case .available: "Update available"
        case .upToDate: "Upkeep is up to date"
        case .failed: "Couldn’t check for updates"
        case .installing: "Installing update"
        case .checking: "Checking for updates"
        case .idle: "Upkeep updates"
        }
    }

    private var symbol: String {
        switch controller.phase {
        case .available: "arrow.down.circle.fill"
        case .upToDate: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "arrow.triangle.2.circlepath"
        }
    }

    private var tint: Color {
        switch controller.phase {
        case .available: .accentColor
        case .upToDate: .green
        case .failed: .orange
        default: .secondary
        }
    }

    private var status: String {
        switch controller.phase {
        case .idle: "Not checked yet"
        case .checking: "Checking…"
        case let .upToDate(date): "Last checked \(date.formatted(date: .omitted, time: .shortened))"
        case let .available(release): "Version \(release.version) is available"
        case let .installing(release): "Installing \(release.version)…"
        case .failed: "Last check failed"
        }
    }
}
