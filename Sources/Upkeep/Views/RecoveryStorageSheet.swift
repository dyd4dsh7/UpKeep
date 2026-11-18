import AppKit
import SwiftUI

struct RecoveryStorageSheet: View {
    @UpkeepStoreReference private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @UpkeepState private var storage: RecoveryStorage?
    @UpkeepState private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceSummary(title: "Recovery Storage", detail: "Local backups for supported app restores.", systemImage: "externaldrive")
            if let storage {
                storageContents(storage)
            } else if loading {
                ProgressView("Reading backup storage…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WorkspaceEmptyState("Storage information unavailable", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Upkeep couldn’t read the local backup inventory."))
            }

            WorkspaceDialogFooter {
                if let storage {
                    Button("Show Backup Folder", systemImage: "folder") {
                        NSWorkspace.shared.open(storage.directory)
                    }
                    .help(storage.directory.path)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(width: 560, height: 450)
        .upkeepWorkspaceAppearance()
        .task {
            storage = await store.recoveryStorage()
            loading = false
        }
    }

    private func storageContents(_ storage: RecoveryStorage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InspectorSection(title: "Retention") {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(storage.unknownSizes
                             ? "Retention budget: \(size(storage.byteLimit))"
                             : "\(size(storage.measuredBytes)) of \(size(storage.byteLimit))")
                            .font(.title3.weight(.semibold).monospacedDigit())
                        if !storage.unknownSizes, storage.byteLimit > 0 {
                            ProgressView(value: Double(min(storage.measuredBytes, storage.byteLimit)), total: Double(storage.byteLimit))
                                .accessibilityLabel("Backup storage budget used")
                        } else if storage.unknownSizes {
                            Text("The size of one or more backups is unavailable.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Upkeep keeps up to three backups per app and twenty in total. Protected recovery backups can exceed the storage budget.")
                            .font(.callout).foregroundStyle(.secondary)
                        if storage.metadataUnavailable {
                            Label("Backups are protected until Upkeep can read their recovery records.", systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(UpkeepColors.warning(in: scheme))
                        }
                    }
                }

                WorkspaceSectionLabel(title: "Retained backups", count: storage.backups.count)
                if storage.backups.isEmpty {
                    Text("No backups are stored.").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(storage.backups) { backup in
                            if backup.id != storage.backups.first?.id { Divider() }
                            backupRow(backup)
                        }
                    }
                    .padding(.horizontal, 14)
                    .upkeepSurface()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UpkeepLayout.pageInset)
        }
    }

    private func backupRow(_ backup: RecoveryStorage.Backup) -> some View {
        HStack(spacing: 10) {
            WorkspaceGlyph(systemImage: backup.protected ? "lock.shield" : "externaldrive", size: 29)
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: backup.path).lastPathComponent).font(.callout.weight(.medium))
                if backup.protected {
                    Text("Recovery protected").font(.caption).foregroundStyle(.secondary)
                }
            }
            .lineLimit(2)
            Spacer(minLength: 8)
            Text(backup.bytes.map(size) ?? "Size unavailable")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 9)
        .help(backup.path)
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
