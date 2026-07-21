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
        .padding(.vertical, 6)
    }
}

struct VersionTransitionView: View {
    let current: String
    var latest: String?

    var body: some View {
        Group {
            if let latest, latest != current {
                HStack(spacing: 5) {
                    Text(current)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
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
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: 128, alignment: .trailing)
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
