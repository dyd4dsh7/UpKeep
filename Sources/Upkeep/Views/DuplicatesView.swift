import AppKit
import SwiftUI

/// Apps, command-line tools and runtimes installed more than once, with a way
/// to keep one copy and remove the rest.
struct DuplicatesView: View {
    @UpkeepStoreReference private var store
    @EnvironmentObject private var settings: AppSettings
    @UpkeepState private var pending: PendingRemoval?

    private enum PendingRemoval: Identifiable {
        case keepOnly(DuplicateMember, DuplicateGroup)
        case remove(DuplicateMember)

        var id: String {
            switch self {
            case let .keepOnly(member, group): "keep|\(group.id)|\(member.id)"
            case let .remove(member): "remove|\(member.id)"
            }
        }
    }

    var body: some View {
        let groups = store.duplicateGroups
        VStack(spacing: 0) {
            if groups.isEmpty {
                WorkspaceEmptyState(
                    "No duplicates found", systemImage: "checkmark.seal.fill",
                    description: Text(settings.ignoredDuplicateGroups.isEmpty
                        ? "Apps, command-line tools and runtimes installed more than once appear here."
                        : "Groups you marked Not a Duplicate are hidden.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .upkeepStateTransition()
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.members) { member in
                                row(member, in: group)
                            }
                        } header: {
                            header(for: group)
                        }
                    }
                }
                .upkeepContentList()
                .upkeepStateTransition()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            WorkspaceSummary(title: "Duplicates",
                detail: summary(groups),
                systemImage: SidebarDestination.duplicates.headerSystemImage)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    settings.restoreIgnoredDuplicateGroups()
                } label: {
                    Label("Show Hidden Groups", systemImage: "eye")
                }
                .disabled(settings.ignoredDuplicateGroups.isEmpty)
                .help(settings.ignoredDuplicateGroups.isEmpty
                      ? "No groups are hidden"
                      : "Show the \(settings.ignoredDuplicateGroups.count) groups marked Not a Duplicate")
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }
        ), titleVisibility: .visible, presenting: pending) { pending in
            switch pending {
            case let .keepOnly(member, group):
                Button("Keep This, Remove \(removableOthers(of: member, in: group).count)", role: .destructive) {
                    Task { await store.keepOnly(member, in: group) }
                }
            case let .remove(member):
                Button(removeTitle(member), role: .destructive) {
                    Task { await store.remove(member) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(confirmationMessage(pending))
        }
    }

    private func summary(_ groups: [DuplicateGroup]) -> String {
        let copies = groups.filter { $0.kind != .runtimeVersions }
        let runtimes = groups.count - copies.count
        var parts = [WorkspaceSummary.count(copies.reduce(0) { $0 + $1.members.count - 1 }, "extra copy", "extra copies")]
        if runtimes > 0 { parts.append(WorkspaceSummary.count(runtimes, "runtime with several versions", "runtimes with several versions")) }
        return parts.joined(separator: " · ")
    }

    private func header(for group: DuplicateGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
                Text(group.kind.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Not a Duplicate") { settings.setDuplicateGroupIgnored(true, id: group.id) }
                .buttonStyle(.borderless)
                .font(.caption)
                .textCase(nil)
                .help("Hide this group. Show Hidden Groups in the toolbar brings it back.")
        }
        .padding(.vertical, 4)
    }

    private func row(_ member: DuplicateMember, in group: DuplicateGroup) -> some View {
        let isWorking = store.isWorking(on: member)
        let others = removableOthers(of: member, in: group)
        return StandardItemRow(isSelected: false) {
            icon(for: member)
        } content: {
            ItemIdentityView(title: member.name, detail: member.location)
        } accessories: {
            if group.newestID == member.id, Set(group.members.map(\.version)).count > 1 {
                InfoChip(text: "Newest", tint: .green)
            }
            if case let .app(app) = member, store.isRunning(app) {
                RunningBadge()
            }
            Text(member.version)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if group.kind == .runtimeVersions {
                // Projects can depend on any version, so versions are removed one at a time.
                Button {
                    pending = .remove(member)
                } label: {
                    WorkingActionLabel(isWorking: isWorking, idleTitle: "Remove", workingTitle: "Removing…")
                }
                .listRowPrimaryAction()
                .disabled(!store.canRemove(member) || isWorking)
                .help(store.canRemove(member) ? "Uninstall this version" : "Upkeep can’t uninstall this version")
            } else {
                Button {
                    pending = .keepOnly(member, group)
                } label: {
                    WorkingActionLabel(isWorking: isWorking, idleTitle: "Keep Only This", workingTitle: "Removing…")
                }
                .listRowPrimaryAction()
                .disabled(others.isEmpty || group.members.contains(where: store.isWorking(on:)))
                .help(others.isEmpty ? "The other copies can’t be removed by Upkeep"
                      : "Keep this copy and remove \(others.count) other\(others.count == 1 ? "" : "s")")
            }
        }
        .contextMenu {
            Button("Keep Only This…") { pending = .keepOnly(member, group) }
                .disabled(others.isEmpty)
            if store.canRemove(member) {
                Button(removeTitle(member) + "…", role: .destructive) { pending = .remove(member) }
            }
            Divider()
            switch member {
            case let .app(app):
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            case let .developer(package):
                Button("Open Folder") { openDeveloperPackageFolder(package) }
            case .homebrew:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func icon(for member: DuplicateMember) -> some View {
        switch member {
        case let .app(app): AppIcon(url: app.url, size: 36)
        case let .developer(package): PackageManagerIcon(manager: package.manager)
        case .homebrew: PackageSourceIcon(name: "homebrew", size: 36)
        }
    }

    private func removableOthers(of member: DuplicateMember, in group: DuplicateGroup) -> [DuplicateMember] {
        group.members.filter { $0.id != member.id && store.canRemove($0) }
    }

    private func removeTitle(_ member: DuplicateMember) -> String {
        if case .app = member { return "Move to Trash" }
        return "Uninstall"
    }

    private var confirmationTitle: String {
        switch pending {
        case let .keepOnly(member, _)?: "Keep only \(member.name) in \(member.location)?"
        case let .remove(member)?: "Remove \(member.name) from \(member.location)?"
        case nil: ""
        }
    }

    private func confirmationMessage(_ pending: PendingRemoval) -> String {
        switch pending {
        case let .keepOnly(member, group):
            let others = removableOthers(of: member, in: group)
            let lines = others.map { "• " + $0.removalDescription + "." }
            var text = lines.joined(separator: "\n")
            let kept = group.members.filter { $0.id != member.id && !store.canRemove($0) }
            if !kept.isEmpty { text += "\n\n\(kept.count) other copy can’t be removed by Upkeep and stays." }
            if others.contains(where: { if case .app = $0 { return true } else { return false } }) {
                text += "\n\nApps go to the Trash, and History can put them back."
            }
            return text
        case let .remove(member):
            return member.removalDescription + "."
        }
    }
}
