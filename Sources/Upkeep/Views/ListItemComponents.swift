import AppKit
import SwiftUI

enum UpkeepLayout {
    static let pageInset: CGFloat = 24
    static let sectionSpacing: CGFloat = 16
    static let inspectorMinimumWidth: CGFloat = 320
    static let inspectorIdealWidth: CGFloat = 380
    static let inspectorMaximumWidth: CGFloat = 500
}

enum UpkeepColors {
    static func warning(in scheme: ColorScheme) -> Color {
        scheme == .light ? Color(.sRGB, red: 0.58, green: 0.30, blue: 0.02) : .orange
    }
}

/// Fixed list columns keep the installed version, arrow, new version and
/// action aligned down a list. Rows use `.regular` when there is room and
/// `.compact` when an inspector narrows the list, before wrapping.
struct ListColumnMetrics: Equatable, Sendable {
    let currentVersion: CGFloat
    let latestVersion: CGFloat
    let action: CGFloat

    var versionTransition: CGFloat { currentVersion + latestVersion + 26 }

    /// Action width fits "Open App Store" and "Update & Adopt".
    static let regular = ListColumnMetrics(currentVersion: 88, latestVersion: 104, action: 128)
    static let compact = ListColumnMetrics(currentVersion: 64, latestVersion: 78, action: 120)
}

private struct ListColumnMetricsKey: EnvironmentKey {
    static let defaultValue = ListColumnMetrics.regular
}

extension EnvironmentValues {
    var listColumns: ListColumnMetrics {
        get { self[ListColumnMetricsKey.self] }
        set { self[ListColumnMetricsKey.self] = newValue }
    }
}

/// Reserves the action column on rows without an action.
struct ListActionPlaceholder: View {
    @Environment(\.listColumns) private var columns

    var body: some View {
        Color.clear.frame(width: columns.action, height: 1).accessibilityHidden(true)
    }
}

private struct ItemRowSelectionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var upkeepItemRowSelected: Bool {
        get { self[ItemRowSelectionKey.self] }
        set { self[ItemRowSelectionKey.self] = newValue }
    }
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
        // Alignment guides run in a Sendable closure; read actor-isolated
        // settings here and capture only the calculated offset.
        let separatorLeading: CGFloat = (settings.listDensity == .compact ? 2 : 4)
            + (settings.listDensity == .compact ? 30 : 38) + rowSpacing

        // Every row in a list has the same width and fixed accessory columns,
        // so all rows pick the same variant and stay aligned. Narrow columns
        // come before wrapping, so opening an inspector doesn't reflow rows.
        return ViewThatFits(in: .horizontal) {
            singleLine(columns: .regular)
            singleLine(columns: .compact)
            HStack(alignment: .top, spacing: rowSpacing) {
                rowIcon
                VStack(alignment: .leading, spacing: 8) {
                    content.frame(maxWidth: .infinity, alignment: .leading)
                    rowAccessories
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.listColumns, .compact)
                }
            }
        }
        // Let native Lists measure the wrapped layout's full height after an
        // inspector changes the available width, rather than reuse a short row.
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .environment(\.upkeepItemRowSelected, isSelected)
        .padding(.horizontal, settings.listDensity == .compact ? 2 : 4)
        .padding(.vertical, settings.listDensity == .compact ? 4 : 6)
        .contentShape(Rectangle())
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            separatorLeading
        }
        .listRowSeparator(.visible)
        .animation(reduceMotion ? nil : UpkeepMotion.quick, value: settings.listDensity)
        // Selection changes color only; native row geometry should not animate.
        .upkeepRowTransition()
    }

    private func singleLine(columns: ListColumnMetrics) -> some View {
        HStack(spacing: rowSpacing) {
            rowIcon
            // ViewThatFits measures ideal widths. Pinning the name column's ideal
            // width makes every row choose by the shared columns alone, so long
            // names truncate instead of making only some rows wrap.
            content
                .frame(minWidth: 110, idealWidth: 110, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            rowAccessories
                .environment(\.listColumns, columns)
        }
    }

    private var rowSpacing: CGFloat { settings.listDensity == .compact ? 10 : 12 }

    private var rowIcon: some View {
        icon
            .scaleEffect(settings.listDensity == .compact ? 0.82 : 1)
            .frame(width: settings.listDensity == .compact ? 30 : 38,
                   height: settings.listDensity == .compact ? 30 : 38)
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
    var cveItem: CVEInventoryItem?

    var body: some View {
        VStack(alignment: .leading, spacing: settings.listDensity == .compact ? 1 : 4) {
            HStack(spacing: 7) {
                // The name keeps layout priority, so in a narrow row badges
                // shorten before the name can be squeezed out.
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                    .help(title)
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
                if let cveItem {
                    CVEStatusBadge(item: cveItem)
                        .lineLimit(1)
                }
            }
            Text(detail)
                .font(settings.listDensity == .compact ? .caption : .subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(detail)
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

struct ScanToolbarButton: View {
    @UpkeepStoreReference private var store

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
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: 104, alignment: .trailing)
    }
}

struct VersionTransitionView: View {
    @Environment(\.upkeepItemRowSelected) private var isSelected
    @Environment(\.listColumns) private var columns
    let current: String
    var latest: String?
    var usesFixedWidth = true

    var body: some View {
        Group {
            if let latest, latest != current {
                HStack(spacing: 5) {
                    Text(current)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                        .frame(width: usesFixedWidth ? columns.currentVersion : nil,
                               alignment: .trailing)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(latest)
                        .fontWeight(.semibold)
                        .foregroundStyle(isSelected ? Color.primary : .accentColor)
                        .truncationMode(.middle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background((isSelected ? Color.primary : Color.accentColor).opacity(0.11),
                                    in: RoundedRectangle(cornerRadius: 5))
                        .frame(width: usesFixedWidth ? columns.latestVersion : nil,
                               alignment: .leading)
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
        .font(.system(.callout, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: usesFixedWidth ? columns.versionTransition : nil,
               alignment: usesFixedWidth ? .trailing : .leading)
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
    @Environment(\.listColumns) private var columns

    func body(content: Content) -> some View {
        content
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: columns.action, alignment: .trailing)
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
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(color)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Menu { options } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Update options")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions }
                VStack(alignment: .leading, spacing: 10) { actions }
            }
        }
        .upkeepOutlinedInspectorCard()
        .upkeepAnimated(for: title)
    }
}

private struct OutlinedInspectorCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .upkeepSurface()
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
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(UpkeepPalette.surface(in: scheme))
            .environment(\.defaultMinListRowHeight, settings.listDensity == .compact ? 34 : 46)
    }
}

extension View {
    func upkeepContentList() -> some View {
        modifier(ContentListStyle())
    }
}
