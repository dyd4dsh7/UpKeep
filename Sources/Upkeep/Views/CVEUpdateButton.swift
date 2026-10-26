import SwiftUI

struct CVEUpdateButton: View {
    @UpkeepStoreReference private var store
    let item: CVEInventoryItem

    var body: some View {
        if let action = store.cveUpdateAction(for: item) {
            Button {
                Task { await store.updateCVESoftware(item) }
            } label: {
                WorkingActionLabel(isWorking: store.isUpdatingCVESoftware(action),
                                   idleTitle: action.title, phase: store.updatePhase(for: action.operation))
            }
            .buttonStyle(.bordered)
            .disabled(store.isUpdatingCVESoftware(action))
            .help("Available version: \(action.version). Review the advisory’s fixed releases; this update may not address every CVE.")
            .accessibilityLabel("\(action.title) \(item.name) to \(action.version)")
        }
    }
}
