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
    @State private var showsCleanup = false

    var body: some View {
        Button { showsCleanup = true } label: {
            Label("Cleanup", systemImage: "trash")
        }
        .toolbarControlLabel("Review package cleanup")
        .disabled(targets.isEmpty)
        .sheet(isPresented: $showsCleanup) {
            PackageCleanupSheet(targets: targets, result: $result)
                .environmentObject(store)
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
