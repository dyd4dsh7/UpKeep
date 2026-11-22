import SwiftUI

/// The single inspector layout for applications, packages, and models.
struct InfoPanel<Header: View, Content: View>: View {
    @UpkeepStoreReference private var store
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                header
                Button {
                    store.clearInspectorSelection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Close details")
                .accessibilityLabel("Close details")
                // No Escape shortcut: it would steal Escape from search and text fields.
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(UpkeepLayout.pageInset)
                .background(UpkeepPalette.surface(in: scheme))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: UpkeepLayout.sectionSpacing) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(UpkeepLayout.pageInset)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}

struct InfoPanelHeader<Icon: View, Detail: View>: View {
    let title: String
    @ViewBuilder let icon: Icon
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title2.weight(.semibold)).lineLimit(2)
                    .tracking(-0.35)
                    .accessibilityAddTraits(.isHeader)
                    .textSelection(.enabled)
                detail.font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
