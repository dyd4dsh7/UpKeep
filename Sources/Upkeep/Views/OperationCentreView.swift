import SwiftUI

struct OperationCentreView: View {
    @UpkeepStoreReference private var store
    let execution: UpkeepUpdateExecutionState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @UpkeepState private var checking = Set<OperationID>()

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceSummary(title: "Operations", detail: "", systemImage: "list.bullet.rectangle")
            if execution.activities.isEmpty && execution.completedOperations.isEmpty {
                WorkspaceEmptyState("No update activity", systemImage: "checkmark.circle",
                    description: Text("Active and recent operations appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !execution.activities.isEmpty {
                            activeOperations
                        }
                        if !execution.completedOperations.isEmpty {
                            WorkspaceSectionLabel(title: "Recent operations", count: execution.completedOperations.count)
                            ForEach(execution.completedOperations) { completed in
                                completedOperation(completed)
                            }
                        }
                    }
                    .padding(UpkeepLayout.pageInset)
                }
            }
            WorkspaceDialogFooter {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(minWidth: 420, idealWidth: 560, minHeight: 300, idealHeight: 420)
        .upkeepWorkspaceAppearance()
    }

    private var activeOperations: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkspaceSectionLabel(title: "In progress", count: execution.activities.count)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                ForEach(execution.activities.keys.sorted {
                    (execution.activities[$0]?.startedAt ?? .distantPast)
                        < (execution.activities[$1]?.startedAt ?? .distantPast)
                }, id: \.self) { operation in
                    if let activity = execution.activities[operation] {
                        HStack(spacing: 12) {
                            WorkspaceGlyph(systemImage: "arrow.clockwise", size: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(activity.label).font(.headline)
                                Text(activity.phase.title).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(elapsed(from: activity.startedAt, to: timeline.date))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .upkeepOutlinedInspectorCard()
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func completedOperation(_ completed: CompletedOperation) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(completed.label).font(.headline)
                Spacer(minLength: 8)
                Text(elapsed(from: completed.startedAt, to: completed.finishedAt))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(completed.result.rawValue)
                .foregroundStyle(.secondary)
            if let verification = completed.verification {
                Text("Requested: \(verification.requested) · Installed: \(verification.observed)")
                    .font(.caption)
                    .textSelection(.enabled)
                Text(verification.targetReached ? "Requested version reached" : "Requested version not reached")
                    .font(.caption)
                    .foregroundStyle(verification.targetReached ? Color.secondary : UpkeepColors.warning(in: colorScheme))
            }
            if let commandError = completed.commandError {
                Text("Command reported: \(commandError)")
                    .font(.caption)
                    .foregroundStyle(UpkeepColors.warning(in: colorScheme))
                    .textSelection(.enabled)
            }
            DisclosureGroup("Command log") {
                Text(completed.commandLog.isEmpty ? "No command output was captured for this operation." : completed.commandLog)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            HStack {
                Button(checking.contains(completed.operation) ? "Checking…" : "Check Again") {
                    checking.insert(completed.operation)
                    Task {
                        await store.checkCompletedOperation(completed.operation)
                        checking.remove(completed.operation)
                    }
                }
                .disabled(checking.contains(completed.operation)
                    || !store.canCheckOperation(completed.operation)
                    || store.isWorking(completed.operation))
                if store.canRetryOperation(completed.operation) {
                    Button("Retry Current Update") {
                        dismiss()
                        Task { await store.retryCompletedOperation(completed.operation) }
                    }
                    .disabled(checking.contains(completed.operation))
                }
            }
        }
        .upkeepOutlinedInspectorCard()
        .accessibilityElement(children: .contain)
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        Duration.seconds(max(0, end.timeIntervalSince(start))).formatted(.time(pattern: .minuteSecond))
    }
}
