import SwiftUI

struct StandardItemRow<Icon: View, Content: View, Accessories: View>: View {
    @EnvironmentObject private var settings: AppSettings
    private let icon: Icon
    private let content: Content
    private let accessories: Accessories

    init(
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessories: () -> Accessories
    ) {
        self.icon = icon()
        self.content = content()
        self.accessories = accessories()
    }

    var body: some View {
        HStack(spacing: settings.listDensity == .compact ? 9 : 12) {
            icon
                .scaleEffect(settings.listDensity == .compact ? 0.78 : 1)
                .frame(width: settings.listDensity == .compact ? 30 : 36,
                       height: settings.listDensity == .compact ? 30 : 36)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            HStack(spacing: 10) {
                accessories
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, settings.listDensity == .compact ? 3 : 8)
        .listRowSeparator(.hidden)
        .animation(.snappy(duration: 0.18), value: settings.listDensity)
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

    var body: some View {
        VStack(alignment: .leading, spacing: settings.listDensity == .compact ? 1 : 3) {
            HStack(spacing: 7) {
                Text(title).font(.body.weight(.semibold)).lineLimit(1)
                if isRunning { RunningIndicator() }
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
                .font(settings.listDensity == .compact ? .caption : .callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ListDensityButton: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) {
                settings.listDensity = settings.listDensity == .comfortable ? .compact : .comfortable
            }
        } label: {
            ListControlLabel(
                systemImage: "arrow.up.and.down.text.horizontal",
                isActive: settings.listDensity == .compact
            )
        }
        .buttonStyle(.plain)
        .frame(width: 30, height: 26)
        .fixedSize()
        .help(settings.listDensity == .compact ? "Use comfortable rows" : "Use compact rows")
        .accessibilityLabel(settings.listDensity == .compact ? "Use comfortable rows" : "Use compact rows")
    }
}

struct ListControlLabel: View {
    let systemImage: String
    var isActive = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .frame(width: 30, height: 26)
            .contentShape(Rectangle())
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
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: 92, alignment: .trailing)
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
                        .foregroundStyle(.primary)
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
        .font(.callout.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: usesFixedWidth ? 190 : nil, alignment: usesFixedWidth ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }
}

struct MoreMenuIcon: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .accessibilityLabel("More")
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

struct RunningIndicator: View {
    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 7, height: 7)
            .help("This app is currently running")
            .accessibilityLabel("Running")
    }
}
