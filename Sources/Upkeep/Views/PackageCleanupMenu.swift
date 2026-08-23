import SwiftUI

struct PackageCleanupContainer<Content: View>: View {
    @Binding var result: PackageCleanupResult?
    let contentIdentity: [String]
    @ViewBuilder let content: Content

    init(
        result: Binding<PackageCleanupResult?>,
        contentIdentity: [String],
        @ViewBuilder content: () -> Content
    ) {
        _result = result
        self.contentIdentity = contentIdentity
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let result {
                PackageCleanupResultBanner(result: result) {
                    self.result = nil
                }
                Divider()
            }
            content
        }
        .upkeepAnimated(for: contentIdentity)
        .upkeepAnimated(for: result?.id)
    }
}

struct PackageCleanupMenu: View {
    @EnvironmentObject private var store: UpkeepStore
    let targets: [PackageCleanupTarget]
    @Binding var result: PackageCleanupResult?
    @State private var estimate: PackageCleanupEstimate?
    @State private var scanningTargetID: String?

    var body: some View {
        Group {
            if targets.count == 1, let target = targets.first {
                Button {
                    scan(target)
                } label: {
                    cleanupLabel
                }
                .disabled(store.isWorking(.packageCleanup(target.id)))
            } else {
                Menu {
                    ForEach(targets) { target in
                        Button {
                            scan(target)
                        } label: {
                            Label("Check \(target.kind.cleanupSubject)…", systemImage: "magnifyingglass")
                        }
                        .disabled(store.isWorking(.packageCleanup(target.id)))
                    }
                } label: {
                    cleanupLabel
                }
            }
        }
        .toolbarControlLabel("Check package manager cleanup")
        .disabled(targets.isEmpty || isCleaning)
        .confirmationDialog(
            estimate?.dialogTitle ?? "Review Cleanup",
            isPresented: Binding(
                get: { estimate != nil },
                set: { if !$0 { estimate = nil } }
            ),
            presenting: estimate
        ) { estimate in
            if estimate.shouldOfferCleanup {
                Button("Run \(estimate.target.commandDescription)", role: .destructive) {
                    let target = estimate.target
                    self.estimate = nil
                    Task { result = await store.cleanUp(target) }
                }
                Button("Cancel", role: .cancel) { self.estimate = nil }
            } else {
                Button("Done", role: .cancel) { self.estimate = nil }
            }
        } message: { estimate in
            if estimate.shouldOfferCleanup {
                Text("\(estimate.confirmationMessage)\n\n\(estimate.target.kind.confirmationMessage)\n\nCommand: \(estimate.target.commandDescription)")
            } else {
                Text(estimate.confirmationMessage)
            }
        }
    }

    private var cleanupLabel: some View {
        HStack(spacing: 6) {
            if scanningTargetID != nil {
                ProgressView().controlSize(.small)
                Text("Scanning…")
            } else if isCleaning {
                ProgressView().controlSize(.small)
                Text("Cleaning…")
            } else {
                Image(systemName: "trash")
                Text("Cleanup")
            }
        }
        .fixedSize()
    }

    private var isCleaning: Bool {
        targets.contains { store.isWorking(.packageCleanup($0.id)) }
    }

    private func scan(_ target: PackageCleanupTarget) {
        result = nil
        scanningTargetID = target.id
        Task {
            let scannedEstimate = await store.scanCleanup(target)
            scanningTargetID = nil
            if let scannedEstimate { estimate = scannedEstimate }
        }
    }
}

struct PackageCleanupResultBanner: View {
    let result: PackageCleanupResult
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.headline)
                Text(result.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Text(result.target.commandDescription)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss cleanup result")
            .accessibilityLabel("Dismiss cleanup result")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
