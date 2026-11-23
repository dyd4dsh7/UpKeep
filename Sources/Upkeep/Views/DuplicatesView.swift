import AppKit
import SwiftUI

/// Apps, command-line tools and runtimes installed more than once, grouped by
/// kind. Each group is a card; the copy in use (or else the newest) is the
/// recommended one to keep.
struct DuplicatesView: View {
    @UpkeepStoreReference private var store
    @EnvironmentObject private var settings: AppSettings
    @UpkeepState private var pending: PendingRemoval?
    @State private var activeIDs: Set<String> = []
    /// Homebrew formulae that can replace a group, by group ID.
    @State private var replacements: [String: String] = [:]

    private enum PendingRemoval: Identifiable {
        case keepOnly(DuplicateMember, DuplicateGroup)
        case remove(DuplicateMember)
        case useHomebrew(DuplicateGroup, String)

        var id: String {
            switch self {
            case let .keepOnly(member, group): "keep|\(group.id)|\(member.id)"
            case let .remove(member): "remove|\(member.id)"
            case let .useHomebrew(group, _): "homebrew|\(group.id)"
            }
        }
    }

    private static let kindOrder: [DuplicateGroup.Kind] = [.appCopies, .packageCopies, .twoInstallers, .runtimeVersions]

    var body: some View {
        let groups = store.duplicateGroups
        Group {
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        ForEach(Self.kindOrder, id: \.self) { kind in
                            let kindGroups = groups.filter { $0.kind == kind }
                            if !kindGroups.isEmpty { kindSection(kind, groups: kindGroups) }
                        }
                    }
                    .frame(maxWidth: 900, alignment: .leading)
                    .padding(UpkeepLayout.pageInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .upkeepStateTransition()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            WorkspaceSummary(title: "Duplicates", detail: summary(groups),
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
        .task(id: groups.map(\.id)) {
            activeIDs = await store.activeDuplicateMemberIDs(groups)
            var found: [String: String] = [:]
            for group in groups {
                if let formula = await store.homebrewReplacement(for: group) { found[group.id] = formula }
            }
            replacements = found
        }
        .confirmationDialog(confirmationTitle, isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }
        ), titleVisibility: .visible, presenting: pending) { pending in
            switch pending {
            case let .keepOnly(member, group):
                let count = removableOthers(of: member, in: group).count
                Button("Keep This, Remove \(count) Other\(count == 1 ? "" : "s")", role: .destructive) {
                    Task { await store.keepOnly(member, in: group) }
                }
            case let .remove(member):
                Button(removeTitle(member), role: .destructive) {
                    Task { await store.remove(member) }
                }
            case let .useHomebrew(group, formula):
                Button("Install with Homebrew, Remove \(group.members.count)") {
                    Task { await store.replaceWithHomebrew(group, formula: formula) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(confirmationMessage(pending))
        }
    }

    // MARK: Sections and cards

    private func kindSection(_ kind: DuplicateGroup.Kind, groups: [DuplicateGroup]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(kind.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(groups) { card(for: $0) }
        }
    }

    private func card(for group: DuplicateGroup) -> some View {
        let recommended = recommendedID(in: group)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                icon(for: group.members[0], size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title).font(.headline)
                    Text(groupDetail(group)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if let formula = replacements[group.id] {
                    Button {
                        pending = .useHomebrew(group, formula)
                    } label: {
                        WorkingActionLabel(isWorking: store.isReplacingWithHomebrew(group),
                                           idleTitle: "Use Homebrew Instead", workingTitle: "Installing…")
                    }
                    .buttonStyle(.bordered)
                    .disabled(group.members.contains(where: store.isWorking(on:)) || store.isReplacingWithHomebrew(group))
                    .help("Install \(formula) once with Homebrew so it works with every Node.js version, then remove these copies")
                }
                Button("Not a Duplicate") { settings.setDuplicateGroupIgnored(true, id: group.id) }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .help("Hide this group. Show Hidden Groups in the toolbar brings it back.")
            }
            .padding(.horizontal, UpkeepLayout.cardPadding)
            .padding(.vertical, 12)
            if group.isPerNodeVersion {
                Label("Each Node.js version managed by nvm has its own global packages, so a copy only runs while its Node.js version is active.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, UpkeepLayout.cardPadding)
                    .padding(.bottom, 12)
            }
            ForEach(group.members) { member in
                Divider().padding(.leading, UpkeepLayout.cardPadding)
                memberRow(member, in: group, isRecommended: member.id == recommended)
            }
        }
        .upkeepSurface(radius: UpkeepLayout.cardRadius)
    }

    private func memberRow(_ member: DuplicateMember, in group: DuplicateGroup, isRecommended: Bool) -> some View {
        let isWorking = store.isWorking(on: member)
        let groupBusy = group.members.contains(where: store.isWorking(on:))
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.place).fontWeight(.medium).lineLimit(1)
                    if activeIDs.contains(member.id) {
                        InfoChip(text: inUseTitle(member), systemImage: "checkmark", tint: .green)
                            .help(inUseHelp(member))
                    }
                    if group.newestID == member.id, Set(group.members.map(\.version)).count > 1 {
                        InfoChip(text: "Newest", tint: .blue)
                    }
                }
                Text(member.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(member.path)
            }
            Spacer(minLength: 12)
            Text(member.version)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            actionButton(member, in: group, isRecommended: isRecommended, isWorking: isWorking, groupBusy: groupBusy)
        }
        .padding(.horizontal, UpkeepLayout.cardPadding)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu { contextMenu(member, in: group) }
    }

    @ViewBuilder
    private func actionButton(_ member: DuplicateMember, in group: DuplicateGroup,
                              isRecommended: Bool, isWorking: Bool, groupBusy: Bool) -> some View {
        if group.kind == .runtimeVersions {
            // Projects can depend on any version, so versions go one at a time.
            Button { pending = .remove(member) } label: {
                WorkingActionLabel(isWorking: isWorking, idleTitle: "Remove", workingTitle: "Removing…")
                    .frame(minWidth: 64)
            }
            .buttonStyle(.bordered)
            .disabled(!store.canRemove(member) || groupBusy)
            .help(store.canRemove(member) ? "Uninstall this version" : "Upkeep can’t uninstall this version")
        } else {
            let others = removableOthers(of: member, in: group)
            let button = Button { pending = .keepOnly(member, group) } label: {
                WorkingActionLabel(isWorking: isWorking, idleTitle: "Keep", workingTitle: "Removing…")
                    .frame(minWidth: 64)
            }
            .disabled(others.isEmpty || groupBusy)
            .help(others.isEmpty ? "Upkeep can’t remove the other copies"
                  : "Keep this copy and remove \(others.count) other\(others.count == 1 ? "" : "s")")
            if isRecommended {
                button.buttonStyle(.borderedProminent)
            } else {
                button.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(_ member: DuplicateMember, in group: DuplicateGroup) -> some View {
        if group.kind != .runtimeVersions {
            Button("Keep Only This…") { pending = .keepOnly(member, group) }
                .disabled(removableOthers(of: member, in: group).isEmpty)
        }
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

    @ViewBuilder
    private func icon(for member: DuplicateMember, size: CGFloat) -> some View {
        switch member {
        case let .app(app): AppIcon(url: app.url, size: size)
        case let .developer(package): PackageManagerIcon(manager: package.manager, size: size)
        case .homebrew: PackageSourceIcon(name: "homebrew", size: size)
        }
    }

    // MARK: Text

    private func summary(_ groups: [DuplicateGroup]) -> String {
        let copies = groups.filter { $0.kind != .runtimeVersions }
        let runtimes = groups.count - copies.count
        var parts = [WorkspaceSummary.count(copies.reduce(0) { $0 + $1.members.count - 1 }, "extra copy", "extra copies")]
        if runtimes > 0 {
            parts.append(WorkspaceSummary.count(runtimes, "runtime with several versions", "runtimes with several versions"))
        }
        return parts.joined(separator: " · ")
    }

    private func groupDetail(_ group: DuplicateGroup) -> String {
        let count = group.kind == .runtimeVersions ? "\(group.members.count) versions" : "\(group.members.count) copies"
        guard group.kind != .runtimeVersions else { return count }
        return Set(group.members.map(\.version)).count > 1 ? "\(count) · different versions" : "\(count) · same version"
    }

    /// The copy in use, or else the newest.
    private func recommendedID(in group: DuplicateGroup) -> String? {
        group.members.first { activeIDs.contains($0.id) }?.id ?? group.newestID
    }

    private func inUseTitle(_ member: DuplicateMember) -> String {
        if case .app = member { return "Opens by default" }
        return "In use"
    }

    private func inUseHelp(_ member: DuplicateMember) -> String {
        if case .app = member { return "macOS opens this copy when you open the app" }
        return "This copy runs when you type its command in Terminal, because its folder comes first on your PATH"
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
        case let .keepOnly(member, _)?: "Keep \(member.name) in \(member.place)?"
        case let .remove(member)?: "Remove \(member.name) \(member.version)?"
        case let .useHomebrew(group, formula)?: "Install \(formula) with Homebrew instead of \(group.members.count) copies?"
        case nil: ""
        }
    }

    private func confirmationMessage(_ pending: PendingRemoval) -> String {
        switch pending {
        case let .keepOnly(member, group):
            let others = removableOthers(of: member, in: group)
            var text = others.map { "• " + $0.removalDescription + "." }.joined(separator: "\n")
            if others.contains(where: { activeIDs.contains($0.id) }) {
                text += "\n\nOne of these is the copy in use now. Afterwards, \(member.place) is used instead if it is on your PATH."
            }
            if group.isPerNodeVersion {
                text += "\n\nAfterwards, \(member.name) only works while \(member.place.replacingOccurrences(of: "NVM ", with: "")) is active. To have it with every version, use Homebrew instead."
            }
            let staying = group.members.count - others.count - 1
            if staying > 0 { text += "\n\n\(staying) other cop\(staying == 1 ? "y" : "ies") can’t be removed by Upkeep and stay." }
            if others.contains(where: { if case .app = $0 { return true } else { return false } }) {
                text += "\n\nApps go to the Trash, and History can put them back."
            }
            return text
        case let .remove(member):
            var text = member.removalDescription + "."
            if activeIDs.contains(member.id) {
                text += "\n\nThis is the version in use now. Terminal will use a different version, or none, afterwards."
            }
            return text
        case let .useHomebrew(group, formula):
            var lines = ["Homebrew installs \(formula), so it works whichever Node.js version is active and Homebrew keeps it updated.",
                         "Then these copies are uninstalled:"]
            lines += group.members.map { "• " + $0.removalDescription + "." }
            lines.append("If the Homebrew install fails, nothing is removed.")
            return lines.joined(separator: "\n")
        }
    }
}
