import SwiftUI

struct ScanStatusNotice: View {
    @EnvironmentObject private var store: UpkeepStore
    @State private var showsDetails = false
    let isMacOS: Bool

    private var state: UpdateCheckState { isMacOS ? store.macOSCheckState : store.updateCheckState }
    private var warnings: [ScanWarning] {
        isMacOS ? store.scanWarnings.filter { $0.source == .macOS } : store.scanWarnings
    }

    var body: some View {
        if state == .failed || state == .partial || !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(state == .checking ? "Checking sources again…" : "Update checks need attention",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Retry") { Task { await store.scan() } }
                        .disabled(store.isScanning)
                }
                if !warnings.isEmpty {
                    Button("Source details (\(warnings.count))") { showsDetails = true }
                        .buttonStyle(.link)
                        .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Update source problems").font(.headline)
                                    ForEach(warnings) { warning in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(warning.title).fontWeight(.medium)
                                            Text(warning.detail).foregroundStyle(.secondary)
                                        }
                                        .font(.caption).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(16)
                            }
                            .frame(width: 420, height: 240)
                        }
                } else {
                    Text(state.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.orange.opacity(0.06))
            Divider()
        }
    }
}
