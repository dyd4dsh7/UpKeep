import SwiftUI

struct PackageCleanupSheet: View {
    @UpkeepStoreReference private var store
    @Environment(\.dismiss) private var dismiss
    let targets: [PackageCleanupTarget]
    @Binding var result: PackageCleanupResult?
    @UpkeepState private var selectedID: String
    @UpkeepState private var estimate: PackageCleanupEstimate?
    @UpkeepState private var completed: PackageCleanupResult?
    @UpkeepState private var failure: String?
    @UpkeepState private var isChecking = false
    @UpkeepState private var isCleaning = false
    @UpkeepState private var showsConfirmation = false

    init(targets: [PackageCleanupTarget], result: Binding<PackageCleanupResult?>) {
        self.targets = targets
        _result = result
        _selectedID = UpkeepState(initialValue: targets.first?.id ?? "")
    }

    private var target: PackageCleanupTarget? { targets.first { $0.id == selectedID } }
    private var isBusy: Bool { isChecking || isCleaning }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspaceSummary(title: "Package Cleanup", detail: "Review unused files before removing them.", systemImage: "trash")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if targets.count > 1 {
                        Picker("Package manager", selection: $selectedID) {
                            ForEach(targets) { target in
                                Text(target.kind.cleanupSubject).tag(target.id)
                            }
                        }
                        .disabled(isBusy)
                    }
                    if let target {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(target.kind.cleanupSubject, systemImage: "shippingbox")
                                .font(.headline)
                            Text(target.kind.confirmationMessage)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .upkeepOutlinedInspectorCard()

                        VStack(alignment: .leading, spacing: 7) { status }
                            .upkeepOutlinedInspectorCard()

                        DisclosureGroup("Command details") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(target.commandDescription).font(.callout.monospaced())
                                Text(target.executablePath).font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(24)
            }
            WorkspaceDialogFooter {
                if !isBusy, completed == nil, estimate != nil {
                    Button("Check Again") { Task { await check() } }
                }
                Spacer()
                Button(completed == nil ? "Cancel" : "Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isBusy)
                if !isBusy, completed == nil {
                    if failure != nil || estimate == nil {
                        Button(failure == nil ? "Check for Cleanup" : "Try Again") {
                            Task { await check() }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    } else if estimate?.shouldOfferCleanup == true {
                        Button("Clean Up…") { showsConfirmation = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .frame(width: 530, height: 440)
        .upkeepWorkspaceAppearance()
        .interactiveDismissDisabled(isBusy)
        .onChange(of: selectedID) { _, _ in
            estimate = nil
            completed = nil
            failure = nil
        }
        .confirmationDialog("Clean up \(target?.kind.cleanupSubject ?? "package files")?",
                            isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button("Clean Up", role: .destructive) { Task { await clean() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(estimate?.cleanupConfirmationMessage
                 ?? "The files identified by the package manager will be removed. This cannot be undone in Upkeep.")
        }
    }

    @ViewBuilder private var status: some View {
        if isBusy {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isCleaning ? "Cleaning up…" : "Checking for unused files…").font(.headline)
                    Text(isCleaning ? "Keep this window open until cleanup finishes." : "No files are removed during this check.")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } else if let completed {
            Label(completed.title, systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(.green)
            Text(completed.message).foregroundStyle(.secondary)
        } else if let failure {
            Label("\(target?.title ?? "Package") cleanup needs attention", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(failure).foregroundStyle(.secondary).textSelection(.enabled)
        } else if let estimate {
            VStack(alignment: .leading, spacing: 8) {
                Text(estimate.basis == .unavailable ? "Cleanup estimate unavailable"
                     : estimate.basis == .reclaimable ? "Estimated space to recover" : "Current cache size")
                    .font(.headline)
                if estimate.basis != .unavailable {
                    Text(ByteCountFormatter.string(fromByteCount: estimate.bytes, countStyle: .file))
                        .font(.largeTitle.weight(.semibold).monospacedDigit())
                }
                Text(estimate.basis == .unavailable ? estimate.confirmationMessage
                     : estimate.basis == .cacheFootprintOnly
                     ? "The manager cannot estimate how much it will remove. This is the total cache size; cleanup may recover less or no space."
                     : estimate.shouldOfferCleanup
                     ? "The final amount may differ from this estimate."
                     : "No unused files were found. There is nothing to clean up.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("Ready to check", systemImage: "magnifyingglass").font(.headline)
            Text("Check the selected manager to see its cleanup estimate or cache size. No files are removed until you confirm cleanup.")
                .foregroundStyle(.secondary)
        }
    }

    private func check() async {
        guard !isBusy, let target else { return }
        isChecking = true
        failure = nil
        estimate = nil
        defer { isChecking = false }
        estimate = await store.scanCleanup(target, onError: { failure = $0 })
        if estimate == nil { failure = failure ?? "The check could not start. Try again when other operations finish." }
    }

    private func clean() async {
        guard !isBusy, let target, estimate?.target == target,
              estimate?.shouldOfferCleanup == true else { return }
        isCleaning = true
        failure = nil
        defer { isCleaning = false }
        completed = await store.cleanUp(target, onError: { failure = $0 })
        if let completed {
            result = completed
        } else {
            estimate = nil
            failure = failure ?? "Cleanup could not start. Check again when other operations finish."
        }
    }
}
