import SwiftUI

struct StandardItemRow<Icon: View, Content: View, Accessories: View>: View {
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
        HStack(spacing: 12) {
            icon
                .frame(width: 36, height: 36)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            HStack(spacing: 10) {
                accessories
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
    }
}

struct ItemIdentityView: View {
    let title: String
    let detail: String
    var isRunning = false
    var tag: String?
    var prereleaseChannel: PrereleaseChannel?
    var prereleaseIsInstalled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
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
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

struct RunningIndicator: View {
    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 7, height: 7)
            .help("This app is currently running")
            .accessibilityLabel("Running")
    }
}
