import SwiftUI

struct OperationCentreView: View {
    @UpkeepStoreReference private var store
    let execution: UpkeepUpdateExecutionState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @UpkeepState private var checking = Set<OperationID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Operations").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if execution.activities.isEmpty && execution.completedOperations.isEmpty {
                ContentUnavailableView("No active updates", systemImage: "checkmark.circle",
                    description: Text("Update activity appears here while an operation is running."))
            } else if !execution.activities.isEmpty {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    List(execution.activities.keys.sorted {
                        (execution.activities[$0]?.startedAt ?? .distantPast)
                            < (execution.activities[$1]?.startedAt ?? .distantPast)
                    }, id: \.self) { operation in
                        if let activity = execution.activities[operation] {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(activity.label).font(.headline)
                                    Text(activity.phase.title).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Duration.seconds(max(0, timeline.date.timeIntervalSince(activity.startedAt)))
                                    .formatted(.time(pattern: .minuteSecond)))
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            if !execution.completedOperations.isEmpty {
                Text("Recent operations").font(.headline)
                ScrollView {
                  LazyVStack(alignment: .leading, spacing: 16) {
                   ForEach(execution.completedOperations) { completed in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(completed.label).font(.headline)
                        HStack {
                            Text(completed.result.rawValue)
                            Spacer()
                            Text(Duration.seconds(max(0, completed.finishedAt.timeIntervalSince(completed.startedAt)))
                                .formatted(.time(pattern: .minuteSecond))).monospacedDigit()
                        }.foregroundStyle(.secondary)
                        if let verification = completed.verification {
                            Text("Requested: \(verification.requested) · Installed: \(verification.observed)")
                                .font(.caption).textSelection(.enabled)
                            Text(verification.targetReached ? "Requested version reached" : "Requested version not reached")
                                .font(.caption).foregroundStyle(verification.targetReached ? Color.secondary : UpkeepColors.warning(in: colorScheme))
                        }
                        if let commandError = completed.commandError {
                            Text("Command reported: \(commandError)")
                                .font(.caption).foregroundStyle(UpkeepColors.warning(in: colorScheme)).textSelection(.enabled)
                        }
                        DisclosureGroup("Command log") {
                            Text(completed.commandLog.isEmpty ? "No command output was captured for this operation." : completed.commandLog)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button(checking.contains(completed.operation) ? "Checking…" : "Check again") {
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
                            Button("Retry current update") {
                                dismiss()
                                Task { await store.retryCompletedOperation(completed.operation) }
                            }
                            .disabled(checking.contains(completed.operation))
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .contain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .upkeepOutlinedInspectorCard()
                   }
                  }
                }
            }
        }
        .padding(UpkeepLayout.pageInset)
        .frame(minWidth: 420, idealWidth: 560, minHeight: 300, idealHeight: 420)
    }

}
