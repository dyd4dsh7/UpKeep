import SwiftUI

struct ScanStatusNotice: View {
    @UpkeepStoreReference private var store
    @UpkeepState private var showsDetails = false
    let isMacOS: Bool

    private var state: UpdateCheckState { isMacOS ? store.macOSCheckState : store.updateCheckState }
    private var warnings: [ScanWarning] {
        isMacOS ? store.scanWarnings.filter { $0.source == .macOS } : store.scanWarnings
    }

    var body: some View {
        if store.isScanning {
            scanProgress
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

    private var scanProgress: some View {
        let appProgress = isMacOS ? nil : store.scanState.progress
        return VStack(alignment: .leading, spacing: 6) {
            if let appProgress, appProgress.total > 0 {
                HStack(spacing: 8) {
                    Text("App source checks")
                        .fontWeight(.medium)
                    Text(appProgress.lastSource.rawValue)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(appProgress.completed) of \(appProgress.total)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .upkeepAnimated(for: appProgress.completed, animation: UpkeepMotion.quick)
                }
                ProgressView(
                    value: Double(appProgress.completed),
                    total: Double(appProgress.total)
                )
                .controlSize(.small)
                .accessibilityLabel("App source checks")
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                        .accessibilityHidden(true)
                    Text("Checking enabled sources…")
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, UpkeepLayout.pageInset)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var warningLabel: some View {
        Label(state == .checking ? "Previous check incomplete" : "Some sources couldn’t be checked",
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
                    .accessibilityLabel("Source details, \(WorkspaceSummary.count(warnings.count, "problem", "problems"))")
                    .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                        VStack(spacing: 0) {
                            WorkspaceSummary(title: "Source Problems",
                                detail: WorkspaceSummary.count(warnings.count, "problem", "problems"),
                                systemImage: "exclamationmark.triangle")
                            ScrollView {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(warnings) { warning in
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(warning.title).font(.callout.weight(.semibold))
                                            Text(warning.detail).font(.callout).foregroundStyle(.secondary)
                                        }
                                        .textSelection(.enabled)
                                        .upkeepOutlinedInspectorCard()
                                    }
                                }
                                .padding(UpkeepLayout.pageInset)
                            }
                        }
                        .frame(width: 420, height: 285)
                        .upkeepWorkspaceAppearance()
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
