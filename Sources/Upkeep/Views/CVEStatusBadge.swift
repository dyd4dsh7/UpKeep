import SwiftUI

/// Only findings for the installed version appear in software and update lists.
struct CVEStatusBadge: View {
    @UpkeepStoreReference private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.upkeepItemRowSelected) private var isSelected
    let item: CVEInventoryItem

    var body: some View {
        let status = store.cveScanState.listStatus(for: item)
        if status.showsListBadge {
            let rating = store.cveScanState.results.first { $0.id == item.id }?.advisoryGroups.compactMap(\.severity)
            let highest = CVESeverityRating.highest(rating ?? [])
            let tint = isSelected ? Color.primary : CVEColors.severity(highest?.level, in: colorScheme)
            Button { store.showCVEInfo(for: item) } label: {
                Label {
                    Text(badgeTitle(status: status, highest: highest))
                } icon: {
                    Image(systemName: "exclamationmark.shield")
                }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(tint.opacity(0.10), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.borderless)
            .help("\(item.name) \(item.version): \(highest?.title ?? "Severity unavailable"), \(status.title). \(item.coverage) Open CVE details.")
            .accessibilityLabel("\(item.name) \(item.version): \(highest?.title ?? "Severity unavailable"), \(status.title). Open CVE details")
        }
    }

    private func badgeTitle(status: CVEListStatus, highest: CVESeverityRating?) -> String {
        guard case let .advisories(count, potential) = status else { return status.title }
        let severity = highest?.level.rawValue ?? "Unrated"
        return "\(potential ? "Potential · " : "")\(severity) · \(count)"
    }
}

/// A findings-only summary keeps the inspector header focused on package identity.
struct CVESecuritySummary: View {
    @UpkeepStoreReference private var store
    let item: CVEInventoryItem

    var body: some View {
        let status = store.cveScanState.listStatus(for: item)
        if status.showsListBadge {
            let groups = store.cveScanState.results.first { $0.id == item.id }?.advisoryGroups ?? []
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(status.title).font(.headline)
                            Spacer(minLength: 12)
                            CVESeverityLabel(rating: CVESeverityRating.highest(groups.compactMap(\.severity)))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(status.title).font(.headline)
                            CVESeverityLabel(rating: CVESeverityRating.highest(groups.compactMap(\.severity)))
                        }
                    }
                    Text("Review affected versions and fixed releases before choosing an update.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Review Advisories", systemImage: "arrow.up.forward") {
                        store.showCVEInfo(for: item)
                    }
                    .buttonStyle(.bordered)
                    .help("Review security advisories for \(item.name) \(item.version)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            } label: {
                Label("Security", systemImage: "exclamationmark.shield")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}
