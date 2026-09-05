import SwiftUI

struct PackageCleanupSheet: View {
    @EnvironmentObject private var store: UpkeepStore
    @Environment(\.dismiss) private var dismiss
    let targets: [PackageCleanupTarget]
    @Binding var result: PackageCleanupResult?
    @State private var selectedID: String
    @State private var estimate: PackageCleanupEstimate?
    @State private var completed: PackageCleanupResult?
    @State private var failure: String?
    @State private var isChecking = false
    @State private var isCleaning = false
    @State private var showsConfirmation = false

    init(targets: [PackageCleanupTarget], result: Binding<PackageCleanupResult?>) {
        self.targets = targets
        _result = result
        _selectedID = State(initialValue: targets.first?.id ?? "")
    }

    private var target: PackageCleanupTarget? { targets.first { $0.id == selectedID } }
    private var isBusy: Bool { isChecking || isCleaning }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Package cleanup").font(.title2.weight(.semibold))
                Text("Review unused files before removing them.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)

            Divider()
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
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(target.kind.cleanupSubject, systemImage: "shippingbox")
                                    .font(.headline)
                                Text(target.kind.confirmationMessage)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }

                        status

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
            Divider()
            HStack {
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
                    } else if estimate?.shouldOfferCleanup == true {
                        Button("Clean Up…") { showsConfirmation = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 480)
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
            Text("The files identified by the package manager will be removed. This cannot be undone in Upkeep.")
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
                Text(estimate.basis == .reclaimable ? "Estimated space to recover" : "Current cache size")
                    .font(.headline)
                Text(ByteCountFormatter.string(fromByteCount: estimate.bytes, countStyle: .file))
                    .font(.largeTitle.weight(.semibold).monospacedDigit())
                Text(estimate.basis == .cacheFootprintOnly
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
