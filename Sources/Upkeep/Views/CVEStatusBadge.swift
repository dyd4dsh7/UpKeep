import SwiftUI

/// Only findings for the installed version appear in software and update lists.
struct CVEStatusBadge: View {
    @UpkeepStoreReference private var store
    let item: CVEInventoryItem

    var body: some View {
        let status = store.cveScanState.listStatus(for: item)
        if status.showsListBadge {
            Button { store.showCVEInfo(for: item) } label: {
                Label(status.title, systemImage: "exclamationmark.shield")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .help("\(item.name) \(item.version): \(status.title). \(item.coverage) Open CVE details.")
            .accessibilityLabel("\(item.name) \(item.version): \(status.title). Open CVE details")
        }
    }
}
