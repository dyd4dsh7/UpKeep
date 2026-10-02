import SwiftUI

/// The single inspector layout for applications, packages, and models.
struct InfoPanel<Header: View, Content: View>: View {
    @UpkeepStoreReference private var store
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                header
                Button {
                    store.selectedApp = nil
                    store.updateInspectorSelection = nil
                    store.selectedPackageID = nil
                    store.selectedDeveloperPackageID = nil
                    store.selectedLocalModelID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close details")
                .accessibilityLabel("Close details")
                .keyboardShortcut(.cancelAction)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
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
                    .textSelection(.enabled)
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
