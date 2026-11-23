import SwiftUI

struct LocalModelsView: View {
    @UpkeepStoreReference private var store
    @UpkeepState private var modelPendingUninstall: LocalLLMModel?

    var body: some View {
        let models = sortedModels
        VStack(spacing: 0) {
            if models.isEmpty, store.isScanning || store.isWorking(.localModelScan) {
                WorkspaceScanningState(title: "Checking local models…",
                                       detail: "Models appear here when the check finishes.")
                    .upkeepStateTransition()
            } else if models.isEmpty {
                WorkspaceEmptyState(
                    "No local models found", systemImage: "brain.head.profile",
                    description: Text("Models appear here when Ollama, LM Studio, or the Hugging Face cache has models installed.")
                )
                .upkeepStateTransition()
            } else {
                modelList(models)
                    .upkeepStateTransition()
            }
        }
        .upkeepAnimated(for: models.map(\.id))
        .safeAreaInset(edge: .top, spacing: 0) {
            WorkspaceSummary(title: "Local AI Models",
                detail: "\(WorkspaceSummary.count(models.count, "model", "models")) · \(WorkspaceSummary.count(models.count { $0.isOutdated && !store.isExcluded($0) }, "update", "updates")) available",
                systemImage: "brain.head.profile")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AsyncToolbarButton(
                    title: "Check local models",
                    systemImage: "arrow.clockwise",
                    isWorking: store.isWorking(.localModelScan),
                    action: { _ = await store.scanLocalModels() }
                )
            }
        }
        .localModelUninstallConfirmation($modelPendingUninstall)
    }

    private func modelList(_ models: [LocalLLMModel]) -> some View {
        List(models, selection: $store.navigation.selectedLocalModelID) { model in
            LocalModelRow(
                store: store,
                model: model,
                isSelected: model.id == store.selectedLocalModelID,
                exclusion: store.exclusion(for: model),
                isWorking: store.isWorking(.localModel(model.id)),
                requestUninstall: { modelPendingUninstall = model }
            )
            .equatable()
            .tag(model.id)
        }
        .upkeepContentList()
        .onAppear { ensureModelSelection(in: models) }
        .onChange(of: models.map(\.id)) { _, _ in ensureModelSelection(in: models) }
    }

    private var sortedModels: [LocalLLMModel] {
        store.localModels.sorted { left, right in
            if left.isOutdated != right.isOutdated { return left.isOutdated }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private func ensureModelSelection(in models: [LocalLLMModel]) {
        guard !models.contains(where: { $0.id == store.selectedLocalModelID }) else { return }
        store.selectedLocalModelID = models.first?.id
    }
}

private struct LocalModelRow: View, Equatable {
    let store: UpkeepStore
    let model: LocalLLMModel
    let isSelected: Bool
    let exclusion: UpdateExclusion?
    let isWorking: Bool
    let requestUninstall: () -> Void

    nonisolated static func == (left: Self, right: Self) -> Bool {
        left.model == right.model
            && left.isSelected == right.isSelected
            && left.exclusion == right.exclusion
            && left.isWorking == right.isWorking
    }

    var body: some View {
        StandardItemRow(isSelected: isSelected) {
            LocalModelRuntimeIcon(runtime: model.runtime, size: 36)
        } content: {
            LocalModelIdentityView(model: model)
        } accessories: {
            UpdateVersionAccessory(
                currentVersion: model.installedRevision,
                availableVersion: model.latestRevision,
                showsUpdate: model.isOutdated,
                exclusion: exclusion
            )
            if model.isOutdated && exclusion == nil {
                Button { Task { await store.updateLocalModel(model) } } label: {
                    WorkingActionLabel(
                        isWorking: isWorking,
                        idleTitle: "Update",
                        phase: store.updatePhase(for: .localModel(model.id))
                    )
                }
                    .listRowPrimaryAction()
                    .disabled(isWorking)
            } else {
                ListActionPlaceholder()
            }
        }
        .contextMenu {
            Group {
                if let exclusion {
                    Button("Restore Updates") { store.restore(exclusion) }
                } else {
                    if model.isOutdated {
                        Button("Update") { Task { await store.updateLocalModel(model) } }
                            .disabled(isWorking)
                        Divider()
                    }
                    UpdateExclusionOptions(
                        skipTitle: "Skip This Revision",
                        ignoreTitle: "Ignore \(model.name) Indefinitely",
                        skip: { store.skip(model) }, ignore: { store.ignore(model) },
                        skipFor: { store.skip(model, duration: $0) },
                        ignoreFor: { store.ignore(model, duration: $0) }
                    )
                }
                Divider()
                Button("Uninstall…", role: .destructive, action: requestUninstall)
                    .disabled(isWorking)
            }
        }
    }
}

struct LocalModelDetail: View {
    @UpkeepStoreReference private var store
    @UpkeepState private var modelPendingUninstall: LocalLLMModel?
    let model: LocalLLMModel?

    var body: some View {
        if let model {
            InfoPanel {
                    InfoPanelHeader(title: model.name) {
                        LocalModelRuntimeIcon(runtime: model.runtime, size: 44)
                    } detail: {
                        if let variant = model.variant { Text(variant).font(.title3).foregroundStyle(.secondary).textSelection(.enabled) }

                    }
                } content: {
                    if model.isOutdated {
                        updateCard(model)
                    } else {
                        Label("Model is current", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                    InspectorSection(title: "Model information") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                            GridRow { label("Runtime"); Text(model.runtime.rawValue) }
                            GridRow { label("Installed"); Text(model.installedRevision).monospacedDigit() }
                            GridRow { label("Latest"); Text(model.latestRevision).monospacedDigit() }
                            if let size = model.sizeBytes { GridRow { label("Size"); Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) } }
                            if let modified = model.modifiedAt { GridRow { label("Downloaded"); Text(modified.formatted(date: .abbreviated, time: .shortened)) } }
                            if let homepage = model.homepage { GridRow { label("Source"); Link(homepage.host() ?? "Open model page", destination: homepage) } }
                        }
                    }
                    uninstallButton(model)
                    DisclosureGroup("How updates work") {
                    Text(howUpdatesWork(model.runtime))
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.top, 8)
                    }
                }
                .localModelUninstallConfirmation($modelPendingUninstall)
        } else {
            WorkspaceEmptyState("Select a model", systemImage: "brain.head.profile")
        }
    }

    private func howUpdatesWork(_ runtime: LocalModelRuntime) -> String {
        switch runtime {
        case .ollama:
            "Upkeep compares the installed manifest digest with Ollama’s registry, then uses ollama pull to update."
        case .lmStudio:
            "Upkeep compares the local model file with its Hugging Face repository, then uses LM Studio’s lms get command to refresh it."
        case .huggingFace:
            "Upkeep compares the cached revision with the repository’s main branch on Hugging Face, then uses hf download to refresh the files already in the cache. Install the Hugging Face CLI (hf) to update from Upkeep."
        }
    }

    private func updateCard(_ model: LocalLLMModel) -> some View {
        let isUpdating = store.isWorking(.localModel(model.id))
        return InspectorUpdateStatusCard(
            title: isUpdating ? "Updating…" : "Update available",
            subtitle: isUpdating ? "Running \(model.runtime.rawValue)" : "Available through \(model.runtime.rawValue)",
            systemImage: isUpdating ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.down.circle.fill"
        ) {
            if let exclusion = store.exclusion(for: model) {
                Label(exclusion.mode.rawValue, systemImage: exclusion.mode == .ignored ? "eye.slash" : "forward.end")
                    .foregroundStyle(.orange)
                Button("Restore Updates") { store.restore(exclusion) }.buttonStyle(.borderedProminent)
            } else {
                Button { Task { await store.updateLocalModel(model) } } label: {
                    WorkingActionLabel(
                        isWorking: isUpdating,
                        idleTitle: "Update with \(model.runtime.rawValue)",
                        phase: store.updatePhase(for: .localModel(model.id))
                    )
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUpdating)
            }
        } options: {
            if let exclusion = store.exclusion(for: model) {
                Button("Restore Updates") { store.restore(exclusion) }
            } else {
                UpdateExclusionOptions(
                    skipTitle: "Skip This Revision",
                    ignoreTitle: "Ignore \(model.name) Indefinitely",
                    skip: { store.skip(model) }, ignore: { store.ignore(model) },
                    skipFor: { store.skip(model, duration: $0) },
                    ignoreFor: { store.ignore(model, duration: $0) }
                )
            }
            Divider()
            Button("Uninstall…", role: .destructive) { modelPendingUninstall = model }
                .disabled(isUpdating)
        }
    }

    private func uninstallButton(_ model: LocalLLMModel) -> some View {
        let isWorking = store.isWorking(.localModel(model.id))
        return HStack {
            Spacer(minLength: 0)
            Button(role: .destructive) { modelPendingUninstall = model } label: {
                Label {
                    WorkingActionLabel(isWorking: isWorking, idleTitle: "Uninstall", workingTitle: "Uninstalling…")
                } icon: {
                    Image(systemName: "trash")
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isWorking)
        }
    }

    private func label(_ text: String) -> some View { Text(text).foregroundStyle(.secondary) }
}

struct LocalModelRuntimeIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let runtime: LocalModelRuntime
    let size: CGFloat

    var body: some View {
        Group {
            if let logo = ThirdPartyLogo.image(named: runtime.assetName, in: colorScheme) {
                Image(nsImage: logo).resizable().scaledToFit()
            } else {
                Image(systemName: runtime.systemImage)
                    .resizable().scaledToFit().padding(size * 0.2).foregroundStyle(.blue)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .accessibilityLabel(runtime.rawValue)
    }
}

private struct LocalModelUninstallConfirmation: ViewModifier {
    @UpkeepStoreReference private var store
    @Binding var model: LocalLLMModel?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            model.map { "Uninstall \($0.name)?" } ?? "Uninstall Model?",
            isPresented: Binding(get: { model != nil }, set: { if !$0 { model = nil } }),
            titleVisibility: .visible,
            presenting: model
        ) { model in
            Button("Uninstall", role: .destructive) {
                Task { await store.uninstallLocalModel(model) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text(message(for: model))
        }
    }

    private func message(for model: LocalLLMModel) -> String {
        let size = model.sizeBytes.map { " This frees about \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))." } ?? ""
        switch model.runtime {
        case .ollama:
            return "Ollama will remove \(model.name). Ollama must be running.\(size)"
        case .lmStudio:
            return "The \(model.variant ?? model.name) model file will be moved to the Trash.\(size)"
        case .huggingFace:
            return "The cached copy of \(model.name) will be moved to the Trash.\(size)"
        }
    }
}

extension View {
    func localModelUninstallConfirmation(_ model: Binding<LocalLLMModel?>) -> some View {
        modifier(LocalModelUninstallConfirmation(model: model))
    }
}
