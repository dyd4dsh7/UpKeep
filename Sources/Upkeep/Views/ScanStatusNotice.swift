import SwiftUI

struct ScanStatusNotice: View {
    @UpkeepStoreReference private var store
    @State private var showsDetails = false
    let isMacOS: Bool

    private var state: UpdateCheckState { isMacOS ? store.macOSCheckState : store.updateCheckState }
    private var warnings: [ScanWarning] {
        isMacOS ? store.scanWarnings.filter { $0.source == .macOS } : store.scanWarnings
    }

    var body: some View {
        if store.isScanning, let progress = store.scanState.progress {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checked \(progress.completed) of \(progress.total) app sources · \(progress.lastSource.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, UpkeepLayout.pageInset).padding(.vertical, 8)
            Divider()
        }
        if state == .failed || state == .partial || !warnings.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    warningLabel
                    Spacer(minLength: 12)
                    warningActions
                }
                VStack(alignment: .leading, spacing: 8) {
                    warningLabel
                    warningActions
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, UpkeepLayout.pageInset)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.25))
            Divider()
        }
    }

    private var warningLabel: some View {
        Label(state == .checking ? "Rechecking sources…" : "Some sources couldn’t be checked",
              systemImage: "exclamationmark.triangle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .symbolRenderingMode(.multicolor)
            .fixedSize(horizontal: false, vertical: true)
            .help(state.detail)
    }

    private var warningActions: some View {
        HStack(spacing: 12) {
            if !warnings.isEmpty {
                Button("Details…") { showsDetails = true }
                    .buttonStyle(.link)
                    .accessibilityLabel("Source details, \(warnings.count) problems")
                    .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Source Problems").font(.headline)
                                ForEach(warnings) { warning in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(warning.title).fontWeight(.medium)
                                        Text(warning.detail).foregroundStyle(.secondary)
                                    }
                                    .font(.callout).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(16)
                        }
                        .frame(width: 420, height: 240)
                    }
            } else {
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Retry") { Task { await store.scan() } }
                .disabled(store.isScanning)
        }
    }
}
