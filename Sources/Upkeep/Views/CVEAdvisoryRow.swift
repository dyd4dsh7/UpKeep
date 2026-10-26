import SwiftUI

struct CVEAdvisoryRow: View {
    let item: CVEInventoryItem
    let result: CVEInventoryResult?
    let pendingStatus: String
    var isSelected = false

    private var groups: [CVEAdvisoryGroup] { result?.advisoryGroups ?? [] }
    private var rating: CVESeverityRating? { CVESeverityRating.highest(groups.compactMap(\.severity)) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CVESoftwareIcon(item: item, size: 30).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(item.origin).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 7) {
                    if !groups.isEmpty {
                        CVESeverityLabel(rating: rating, isSelected: isSelected)
                            .layoutPriority(1)
                        Text("·").foregroundStyle(.tertiary)
                    }
                    Text(groups.isEmpty ? (result?.status ?? pendingStatus) : "\(groups.count) \(groups.count == 1 ? "issue" : "issues")")
                        .foregroundStyle(.secondary).lineLimit(1)
                }.font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(accessibilitySummary)")
        .accessibilityHint("Select to review advisories and available update actions.")
        .help("\(item.name) \(item.version)\n\(result?.status ?? pendingStatus)")
    }
    private var accessibilitySummary: String {
        let status: String
        if groups.isEmpty { status = result?.status ?? pendingStatus }
        else {
            let potential: String
            if case .nvd? = item.target { potential = "potential " } else { potential = "" }
            status = "\(rating?.title ?? "Severity unavailable"), \(groups.count) \(potential)\(groups.count == 1 ? "advisory" : "advisories")"
        }
        return "\(item.origin), installed version \(item.version), \(status)"
    }

}

struct CVESoftwareIcon: View {
    @UpkeepStoreReference private var store
    let item: CVEInventoryItem
    let size: CGFloat

    var body: some View {
        Group {
            if let app = store.apps.first(where: { "app|\($0.id)" == item.id }),
               FileManager.default.fileExists(atPath: app.url.path) {
                AppIcon(url: app.url, size: size)
            } else if case let .developer(package)? = item.target {
                PackageManagerIcon(manager: package.manager, size: size)
            } else if item.id.hasPrefix("brew|") {
                PackageSourceIcon(name: "homebrew", size: size)
            } else {
                Image(systemName: item.id.hasPrefix("app|") ? "app" : "shippingbox")
                    .font(.system(size: size * 0.6)).foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }.accessibilityHidden(true)
    }
}

enum CVEColors {
    static func severity(_ level: CVESeverityRating.Level?, in scheme: ColorScheme) -> Color {
        // Strong text contrast on light surfaces; use platform colors on dark surfaces.
        switch level {
        case .critical, .high:
            scheme == .light ? Color(.sRGB, red: 0.72, green: 0.13, blue: 0.13) : .red
        case .medium:
            scheme == .light ? Color(.sRGB, red: 0.58, green: 0.30, blue: 0.02) : .orange
        case .low:
            scheme == .light ? Color(.sRGB, red: 0.08, green: 0.32, blue: 0.68) : .blue
        default: .secondary
        }
    }
}

struct CVESeverityLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let rating: CVESeverityRating?
    var isSelected = false
    private var tint: Color {
        isSelected ? .primary : CVEColors.severity(rating?.level, in: colorScheme)
    }
    var body: some View {
        Label(rating?.title ?? "Unrated", systemImage: rating == nil ? "questionmark.circle" : "exclamationmark.circle.fill")
            .font(.caption.weight(.medium)).foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct CVEAdvisoryDetail: View {
    let item: CVEInventoryItem
    let result: CVEInventoryResult?
    let pendingStatus: String
    var reviewUpdates: () -> Void
    var showSoftware: () -> Void
    private var groups: [CVEAdvisoryGroup] { result?.advisoryGroups ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 14) {
                    CVESoftwareIcon(item: item, size: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                            .accessibilityAddTraits(.isHeader)
                        Text("\(item.origin) · Installed \(item.version)")
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        CVEUpdateButton(item: item).fixedSize()
                        inventoryActions
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 10) {
                        CVEUpdateButton(item: item)
                        inventoryActions
                    }
                }.controlSize(.regular)

                if !groups.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Next step", systemImage: "arrow.up.forward.circle")
                            .font(.subheadline.weight(.semibold))
                        Text(nextStep).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Next step. \(nextStep)")
                    .accessibilityAddTraits(.isStaticText)

                    HStack {
                        Text("Advisories").font(.headline).accessibilityAddTraits(.isHeader)
                        Text("\(groups.count)").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Text("Highest severity first").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(groups) { group in
                            advisory(group)
                            if group.id != groups.last?.id { Divider() }
                        }
                    }
                } else {
                    Label(result?.failure ?? result?.status ?? pendingStatus,
                          systemImage: result?.failure == nil ? "info.circle" : "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Divider()
                Text(item.coverage).font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(.background)
        .accessibilityLabel("Security details for \(item.name)")
        .id(item.id)
    }

    private var inventoryActions: some View {
        HStack(spacing: 10) {
            Button("Show Software", action: showSoftware)
                .fixedSize().help("Open \(item.name) in its software inventory.")
            Menu {
                Button("Review All Updates", action: reviewUpdates)
            } label: {
                Image(systemName: "ellipsis").frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("More actions for \(item.name)")
            .help("More actions for \(item.name)")
        }.fixedSize()
    }

    private func advisory(_ group: CVEAdvisoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    advisoryIdentifier(group).fixedSize()
                    Spacer(minLength: 0)
                    CVESeverityLabel(rating: group.severity).fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    advisoryIdentifier(group)
                    CVESeverityLabel(rating: group.severity)
                }
            }
            if let summary = group.summary {
                Text(summary).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 10) {
                Text("Fixed in").foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
                Text(group.fixedVersions.isEmpty ? "Not listed by the source" : group.fixedVersions.joined(separator: ", "))
                    .textSelection(.enabled)
            }.font(.callout)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fixed releases: \(group.fixedVersions.isEmpty ? "Not listed by the source" : group.fixedVersions.joined(separator: ", "))")
            .accessibilityAddTraits(.isStaticText)
            HStack(alignment: .center, spacing: 12) {
                if let severity = group.severity {
                    Text(severity.method).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Severity unavailable").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu("Read Advisory") {
                    ForEach(group.records) { record in
                        Link("\(sourceName(record)) · \(record.id)", destination: record.url)
                    }
                }.menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Read source advisories for \(group.id)")
                .accessibilityHint("Opens a menu of source records for this advisory.")
                .help("Open the source records for \(group.id). The highest available source rating is shown.")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Advisory \(group.id)")
    }

    private func advisoryIdentifier(_ group: CVEAdvisoryGroup) -> some View {
        Text(group.cveIDs.isEmpty ? group.id : group.cveIDs.joined(separator: " · "))
            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var nextStep: String {
        if case .nvd? = item.target {
            return "Confirm the advisory applies to your Mac and configuration, then review the vendor’s update guidance. After updating, check again."
        }
        if groups.allSatisfy({ $0.fixedVersions.isEmpty }) {
            return "Read the source advisories for fixes or workarounds. A missing fixed release does not mean no fix exists."
        }
        return "Choose a compatible fixed release branch below, update, then refresh your inventory and check again."
    }
    private func sourceName(_ advisory: CVEAdvisory) -> String {
        switch advisory.url.host {
        case "nvd.nist.gov": "NVD"
        case "github.com": "Homebrew"
        default: "OSV"
        }
    }
}
