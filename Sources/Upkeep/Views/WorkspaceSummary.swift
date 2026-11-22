import SwiftUI

/// Shared heading for workspaces, sheets, and settings pages.
struct WorkspaceSummary<Accessory: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 27
    let title: String
    let detail: String
    let systemImage: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 14) {
            WorkspaceGlyph(systemImage: systemImage, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .tracking(-0.85)
                    .accessibilityAddTraits(.isHeader)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(detail)
                }
            }
            Spacer(minLength: 0)
            accessory.fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UpkeepLayout.pageInset)
        .padding(.vertical, 19)
        .background(UpkeepPalette.canvas(in: scheme))
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension WorkspaceSummary where Accessory == EmptyView {
    init(title: String, detail: String, systemImage: String) {
        self.init(title: title, detail: detail, systemImage: systemImage, accessory: { EmptyView() })
    }

    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value.formatted()) \(value == 1 ? singular : plural)"
    }
}
