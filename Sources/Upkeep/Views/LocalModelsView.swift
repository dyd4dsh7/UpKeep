import SwiftUI

struct LocalModelsView: View {
    @EnvironmentObject private var store: UpkeepStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: "Local AI Models",
                subtitle: "\(store.localModels.count) installed · \(store.outdatedLocalModelCount) updates",
                systemImage: "brain.head.profile.fill"
            )
            HStack {
                Text("Installed models · Ollama and LM Studio do not need to be open")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await store.scanLocalModels() } } label: {
                    Label("Check Models", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.workingIDs.contains("local-model-scan"))
            }
            .padding(.horizontal, 20).padding(.bottom, 10)

            if store.localModels.isEmpty {
                ContentUnavailableView(
                    "No local models found", systemImage: "brain.head.profile",
                    description: Text("Models appear here when Ollama or LM Studio has models installed.")
                )
            } else {
                HSplitView {
                    modelList.frame(minWidth: 390, idealWidth: 500)
                    LocalModelDetail(model: selectedModel).frame(minWidth: 310)
                }
            }
        }
    }

    private var modelList: some View {
        List(sortedModels, selection: $store.selectedLocalModelID) { model in
            LocalModelRow(model: model).tag(model.id)
        }
        .listStyle(.inset)
        .onAppear { ensureModelSelection() }
        .onChange(of: store.localModels.map(\.id)) { _, _ in ensureModelSelection() }
    }

    private var selectedModel: LocalLLMModel? {
        guard let id = store.selectedLocalModelID else { return nil }
        return store.localModels.first { $0.id == id }
    }

    private var sortedModels: [LocalLLMModel] {
        store.localModels.sorted { left, right in
            if left.isOutdated != right.isOutdated { return left.isOutdated }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private func ensureModelSelection() {
        guard !store.localModels.contains(where: { $0.id == store.selectedLocalModelID }) else { return }
        store.selectedLocalModelID = store.localModels.first?.id
    }
}

private struct LocalModelRow: View {
    @EnvironmentObject private var store: UpkeepStore
    let model: LocalLLMModel

    var body: some View {
        StandardItemRow {
            LocalModelRuntimeIcon(runtime: model.runtime, size: 36)
        } content: {
            ItemIdentityView(
                title: model.name,
                detail: model.variant.map { "\(model.runtime.rawValue) · \($0)" } ?? model.runtime.rawValue,
                prereleaseChannel: model.prereleaseChannel
            )
        } accessories: {
            if let exclusion = store.exclusion(for: model) {
                ItemStatusView(
                    title: exclusion.mode.rawValue,
                    systemImage: exclusion.mode == .ignored ? "eye.slash" : "forward.end",
                    color: .orange
                )
                InstalledVersionView(version: model.installedRevision)
            } else if model.isOutdated {
                VersionTransitionView(current: model.installedRevision, latest: model.latestRevision)
            } else {
                InstalledVersionView(version: model.installedRevision)
            }
            if model.isOutdated && !store.isExcluded(model) {
                Button("Update") { Task { await store.updateLocalModel(model) } }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(store.workingIDs.contains(model.id))
                    .frame(width: 120)
            } else {
                Color.clear.frame(width: 120, height: 1).accessibilityHidden(true)
            }
        }
        .contextMenu {
            Group {
                if store.isExcluded(model) {
                    if let exclusion = store.exclusion(for: model) {
                        Button("Restore Updates") { store.restore(exclusion) }
                    }
                } else {
                    if model.isOutdated { Button("Skip This Revision") { store.skip(model) } }
                    Button("Ignore \(model.name)") { store.ignore(model) }
                }
            }
        }
    }
}

struct LocalModelDetail: View {
    @EnvironmentObject private var store: UpkeepStore
    let model: LocalLLMModel?

    var body: some View {
        if let model {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LocalModelRuntimeIcon(runtime: model.runtime, size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.name).font(.largeTitle.bold()).textSelection(.enabled)
                        if let variant = model.variant { Text(variant).font(.title3).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                    if model.isOutdated {
                        HStack {
                            Button("Update with \(model.runtime.rawValue)") { Task { await store.updateLocalModel(model) } }
                                .buttonStyle(.borderedProminent).disabled(store.workingIDs.contains(model.id) || store.isExcluded(model))
                            Menu("More") {
                                if store.isExcluded(model), let exclusion = store.exclusion(for: model) {
                                    Button("Restore Updates") { store.restore(exclusion) }
                                } else {
                                    Button("Skip This Revision") { store.skip(model) }
                                    Button("Ignore \(model.name)") { store.ignore(model) }
                                }
                            }
                        }
                    } else {
                        Label("Model is current", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 12) {
                        GridRow { label("Runtime"); Text(model.runtime.rawValue) }
                        GridRow { label("Installed"); Text(model.installedRevision).monospacedDigit() }
                        GridRow { label("Latest"); Text(model.latestRevision).monospacedDigit() }
                        if let size = model.sizeBytes { GridRow { label("Size"); Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) } }
                        if let modified = model.modifiedAt { GridRow { label("Downloaded"); Text(modified.formatted(date: .abbreviated, time: .shortened)) } }
                        if let homepage = model.homepage { GridRow { label("Source"); Link(homepage.host() ?? "Open model page", destination: homepage) } }
                    }
                    .padding(18).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                    Text(model.runtime == .ollama
                         ? "Upkeep compares the installed manifest digest with Ollama’s registry, then uses ollama pull to update."
                         : "Upkeep compares the local model file with its Hugging Face repository, then uses LM Studio’s lms get command to refresh it.")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("Select a model", systemImage: "brain.head.profile")
        }
    }

    private func label(_ text: String) -> some View { Text(text).foregroundStyle(.secondary) }
}

struct LocalModelRuntimeIcon: View {
    let runtime: LocalModelRuntime
    let size: CGFloat

    var body: some View {
        Group {
            if let url = Bundle.module.url(forResource: runtime.assetName, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
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
