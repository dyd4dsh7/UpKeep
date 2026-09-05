import AppKit
import SwiftUI

enum UpkeepLayout {
    static let listActionWidth: CGFloat = 108
    static let inspectorMinimumWidth: CGFloat = 320
    static let inspectorIdealWidth: CGFloat = 380
    static let inspectorMaximumWidth: CGFloat = 500
}

struct StandardItemRow<Icon: View, Content: View, Accessories: View>: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let isSelected: Bool
    private let icon: Icon
    private let content: Content
    private let accessories: Accessories

    init(
        isSelected: Bool = false,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessories: () -> Accessories
    ) {
        self.isSelected = isSelected
        self.icon = icon()
        self.content = content()
        self.accessories = accessories()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: rowSpacing) {
                rowIcon
                content
                    .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                rowAccessories
            }
            HStack(alignment: .top, spacing: rowSpacing) {
                rowIcon
                VStack(alignment: .leading, spacing: 8) {
                    content.frame(maxWidth: .infinity, alignment: .leading)
                    rowAccessories
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, settings.listDensity == .compact ? 2 : 6)
        .padding(.vertical, settings.listDensity == .compact ? 5 : 10)
        .contentShape(Rectangle())
        .listRowSeparator(.visible)
        .animation(reduceMotion ? nil : UpkeepMotion.quick, value: settings.listDensity)
        .upkeepAnimated(for: isSelected, animation: UpkeepMotion.quick)
        .upkeepRowTransition()
    }

    private var rowSpacing: CGFloat { settings.listDensity == .compact ? 10 : 14 }

    private var rowIcon: some View {
        icon
            .scaleEffect(settings.listDensity == .compact ? 0.82 : 1)
            .frame(width: settings.listDensity == .compact ? 32 : 42,
                   height: settings.listDensity == .compact ? 32 : 42)
    }

    private var rowAccessories: some View {
        HStack(spacing: settings.listDensity == .compact ? 8 : 12) {
            accessories
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct ItemIdentityView: View {
    @EnvironmentObject private var settings: AppSettings
    let title: String
    let detail: String
    var isRunning = false
    var tag: String?
    var prereleaseChannel: PrereleaseChannel?
    var prereleaseIsInstalled = false
    var showsIntelWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: settings.listDensity == .compact ? 1 : 4) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if isRunning { RunningIndicator() }
                if showsIntelWarning { IntelAppBadge() }
                if let tag {
                    Text(tag.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                if let prereleaseChannel {
                    PrereleaseBadge(channel: prereleaseChannel, isInstalled: prereleaseIsInstalled)
                }
            }
            Text(detail)
                .font(settings.listDensity == .compact ? .caption : .subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct RefreshingIndicator: View {
    let itemName: String

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Refreshing \(itemName)")
    }
}

struct ListDensityButton: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : UpkeepMotion.quick) {
                settings.listDensity = settings.listDensity == .comfortable ? .compact : .comfortable
            }
        } label: {
            ListControlLabel(
                systemImage: "arrow.up.and.down.text.horizontal",
                isActive: settings.listDensity == .compact
            )
        }
        .toolbarControlLabel(settings.listDensity == .compact ? "Use comfortable rows" : "Use compact rows")
    }
}

struct ScanToolbarButton: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        AsyncToolbarButton(
            title: "Check for updates",
            systemImage: "arrow.clockwise",
            isWorking: store.isScanning,
            action: store.scan
        )
    }
}

struct AsyncToolbarButton: View {
    let title: String
    let systemImage: String
    let isWorking: Bool
    let action: @MainActor () async -> Void

    var body: some View {
        Button { Task { await action() } } label: {
            WorkingToolbarLabel(
                title: title,
                systemImage: systemImage,
                isWorking: isWorking
            )
        }
        .toolbarControlLabel(title)
        .disabled(isWorking)
    }
}

struct WorkingToolbarLabel: View {
    let title: String
    let systemImage: String
    let isWorking: Bool

    var body: some View {
        ZStack {
            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .upkeepStateTransition()
            } else {
                Label(title, systemImage: systemImage)
                    .upkeepStateTransition()
            }
        }
        .upkeepAnimated(for: isWorking, animation: UpkeepMotion.quick)
    }
}

extension View {
    func toolbarControlLabel(_ label: String) -> some View {
        accessibilityLabel(label)
            .help(label)
    }
}

struct ListControlLabel: View {
    let systemImage: String
    var isActive = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .frame(minWidth: 20, minHeight: 20)
            .contentShape(Rectangle())
    }
}

@ToolbarContentBuilder
func upkeepToolbarSpacer() -> some ToolbarContent {
    if #available(macOS 26, *) {
        ToolbarSpacer(.fixed, placement: .primaryAction)
    }
}

struct MenuSelectionLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(title)
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }
}

struct PrereleaseBadge: View {
    let channel: PrereleaseChannel
    var isInstalled = false

    var body: some View {
        Text(isInstalled ? "INSTALLED \(channel.rawValue)" : channel.rawValue)
            .font(.caption2.weight(.bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor, in: Capsule())
            .accessibilityLabel(isInstalled
                ? "Installed \(channel.rawValue) prerelease"
                : "\(channel.rawValue) prerelease")
    }

    private var foregroundColor: Color {
        switch channel {
        case .alpha, .development, .nightly, .snapshot: .orange
        case .beta, .preview, .releaseCandidate, .prerelease: .purple
        }
    }

    private var backgroundColor: Color { foregroundColor.opacity(0.13) }
}

struct ItemStatusView: View {
    let title: String
    let systemImage: String
    var color: Color = .secondary

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 128, alignment: .trailing)
    }
}

struct InstalledVersionView: View {
    let version: String

    var body: some View {
        Text(version)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: 104, alignment: .trailing)
    }
}

struct VersionTransitionView: View {
    let current: String
    var latest: String?
    var usesFixedWidth = true

    var body: some View {
        Group {
            if let latest, latest != current {
                HStack(spacing: 5) {
                    Text(current)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(latest)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(current)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .id(latest == nil || latest == current ? "current" : "update")
        .upkeepStateTransition()
        .upkeepAnimated(for: latest ?? "")
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: usesFixedWidth ? 178 : nil, alignment: usesFixedWidth ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }
}

struct UpdateVersionAccessory: View {
    let currentVersion: String
    let availableVersion: String
    let showsUpdate: Bool
    let exclusion: UpdateExclusion?

    var body: some View {
        if let exclusion {
            ItemStatusView(
                title: exclusion.mode.rawValue,
                systemImage: exclusion.mode == .ignored ? "eye.slash" : "forward.end",
                color: .orange
            )
            InstalledVersionView(version: currentVersion)
        } else if showsUpdate {
            VersionTransitionView(current: currentVersion, latest: availableVersion)
        } else {
            InstalledVersionView(version: currentVersion)
        }
    }
}

struct LocalModelIdentityView: View {
    let model: LocalLLMModel

    var body: some View {
        ItemIdentityView(
            title: model.name,
            detail: model.variant.map { "\(model.runtime.rawValue) · \($0)" }
                ?? model.runtime.rawValue,
            prereleaseChannel: model.prereleaseChannel
        )
    }
}

struct ListRowPrimaryAction: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: UpkeepLayout.listActionWidth, alignment: .trailing)
    }
}

extension View {
    func listRowPrimaryAction() -> some View {
        modifier(ListRowPrimaryAction())
    }
}

struct UpdateExclusionOptions: View {
    let skipTitle: String
    let ignoreTitle: String
    let skip: () -> Void
    let ignore: () -> Void
    let skipFor: (UpdateExclusionDuration) -> Void
    let ignoreFor: (UpdateExclusionDuration) -> Void

    var body: some View {
        Menu("Skip") {
            Button(skipTitle, action: skip)
            Divider()
            ForEach(UpdateExclusionDuration.allCases) { duration in
                Button("For \(duration.title)") { skipFor(duration) }
            }
        }
        Menu("Ignore") {
            Button(ignoreTitle, action: ignore)
            Divider()
            ForEach(UpdateExclusionDuration.allCases) { duration in
                Button("For \(duration.title)") { ignoreFor(duration) }
            }
        }
    }
}

struct InspectorUpdateStatusCard<Actions: View, Options: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var color: Color = .accentColor
    @ViewBuilder let actions: Actions
    @ViewBuilder let options: Options

    init(
        title: String = "Update available",
        subtitle: String,
        systemImage: String = "arrow.down.circle.fill",
        color: Color = .accentColor,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder options: () -> Options
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.color = color
        self.actions = actions()
        self.options = options()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(color)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu { options } label: {
                    Text("Options")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Update options")
            }
            Divider()
            HStack(spacing: 10) { actions }
        }
        .upkeepOutlinedInspectorCard()
        .upkeepAnimated(for: title)
    }
}

private struct OutlinedInspectorCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
    }
}

extension View {
    func upkeepOutlinedInspectorCard() -> some View {
        modifier(OutlinedInspectorCardStyle())
    }
}

struct WorkingActionLabel: View {
    let isWorking: Bool
    let idleTitle: String
    var workingTitle = "Updating…"
    var phase: UpdatePhase?

    var body: some View {
        ZStack {
            if isWorking || phase != nil {
                HStack(spacing: 6) {
                    if phase?.showsProgress != false {
                        ProgressView().controlSize(.small)
                    }
                    Text(phase?.title ?? workingTitle)
                }
                .accessibilityElement(children: .combine)
                .upkeepStateTransition()
            } else {
                Text(idleTitle)
                    .upkeepStateTransition()
            }
        }
        .upkeepAnimated(for: phase?.title ?? (isWorking ? workingTitle : idleTitle), animation: UpkeepMotion.quick)
    }
}

struct RunningIndicator: View {
    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 7, height: 7)
            .help("This app is currently running")
            .accessibilityLabel("Running")
    }
}

/// Shared chrome for item lists; the navigation sidebar retains its native sidebar style.
private struct ContentListStyle: ViewModifier {
    @EnvironmentObject private var settings: AppSettings

    func body(content: Content) -> some View {
        content
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, settings.listDensity == .compact ? 36 : 52)
    }
}

extension View {
    func upkeepContentList() -> some View {
        modifier(ContentListStyle())
    }
}
