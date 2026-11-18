import SwiftUI

struct CVECheckerView: View {
    @UpkeepStoreReference private var store
    @Environment(\.colorScheme) private var colorScheme
    let packages: [DeveloperPackage]
    let apps: [InstalledApp]
    let homebrew: [HomebrewPackage]
    @Bindable var state: CVEScanState
    var makeClient: () -> CVEInventoryClient = { CVEInventoryClient() }
    var reviewUpdates: () -> Void
    var showSoftware: (CVEInventoryItem) -> Void
    @UpkeepState private var selectedID: String?
    @UpkeepState private var showingCoverage = false
    @UpkeepState private var batchReview: CVEBatchReview?
    private struct CVEBatchReview: Identifiable {
        let id = UUID()
        let items: [BatchUpdateItem]
    }

    private var search: String { state.searchText }

    private var inventory: [CVEInventoryItem] {
        apps.map(CVEInventoryItem.init) + homebrew.map(CVEInventoryItem.init) + packages.map(CVEInventoryItem.init)
    }
    private var items: [CVEInventoryItem] { state.checkedAt == nil ? inventory : state.inventory }
    private var resultsByID: [String: CVEInventoryResult] {
        Dictionary(uniqueKeysWithValues: state.results.map { ($0.id, $0) })
    }
    private var findings: Int { state.results.filter { !$0.advisories.isEmpty }.count }
    private var checked: Int { state.results.filter { $0.supported && $0.failure == nil }.count }
    private var incomplete: Int { state.results.filter { $0.supported && $0.failure != nil }.count }
    private var uncovered: Int { items.filter { $0.target == nil }.count }
    private var displayedInventory: [CVEInventoryItem] {
        let results = resultsByID
        return items.filter {
            state.filter.includes($0, result: results[$0.id]) && (search.isEmpty
                || "\($0.name) \($0.version) \($0.origin)".localizedCaseInsensitiveContains(search)
                || results[$0.id]?.advisories.contains { advisory in
                    (advisory.cveIDs + [advisory.id, advisory.summary ?? ""]).contains {
                        $0.localizedCaseInsensitiveContains(search)
                    }
                } == true)
        }.sorted {
            let left = results[$0.id]?.sortPriority ?? ($0.target == nil ? 3 : 2)
            let right = results[$1.id]?.sortPriority ?? ($1.target == nil ? 3 : 2)
            if left != right { return left < right }
            let leftSeverity = results[$0.id]?.advisoryGroups.compactMap(\.severity).map(\.level.rank).max() ?? 0
            let rightSeverity = results[$1.id]?.advisoryGroups.compactMap(\.severity).map(\.level.rank).max() ?? 0
            if leftSeverity != rightSeverity { return leftSeverity > rightSeverity }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            coverageSummary
            Divider()
            if state.running { progress.padding(.horizontal, 22).padding(.vertical, 10) }
            if state.checkedAt != nil, state.inventory != inventory {
                Label("Inventory changed. Check again to refresh these results.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(CVEColors.severity(.medium, in: colorScheme)).padding(.horizontal, 22).padding(.vertical, 8)
            }
            GeometryReader { geometry in
                HSplitView {
                    softwareList
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 340)
                    selectedDetail
                        .frame(minWidth: min(300, geometry.size.width * 0.45), maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: displayedInventory.map(\.id), initial: true) { _, ids in
            if let requested = state.requestedItemID, ids.contains(requested) {
                selectedID = requested
                state.requestedItemID = nil
            } else if selectedID == nil || !ids.contains(selectedID ?? "") {
                selectedID = ids.first
            }
        }
        .onChange(of: state.requestedItemID) { _, requested in
            if let requested, displayedInventory.contains(where: { $0.id == requested }) {
                selectedID = requested
                state.requestedItemID = nil
            }
        }
        .toolbar {
            Button("Coverage & Privacy", systemImage: "info.circle") { showingCoverage = true }
        }
        .sheet(item: $batchReview) { review in
            BatchUpdateSheet(items: review.items, isCVEReview: true)
                .environment(\.upkeepStoreReference, store)
        }
        .sheet(isPresented: $showingCoverage) { coverageSheet }
    }

    private var softwareList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Software").font(.headline)
                Text("\(displayedInventory.count)").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
            searchField.padding(.horizontal, 14).padding(.bottom, 12)
            if displayedInventory.isEmpty {
                WorkspaceEmptyState(emptyTitle, systemImage: search.isEmpty ? "shield" : "magnifyingglass",
                                       description: Text(emptyDescription))
            } else {
                List(displayedInventory, selection: $selectedID) { item in
                    CVEAdvisoryRow(item: item, result: resultsByID[item.id], pendingStatus: pendingStatus(item), isSelected: selectedID == item.id)
                        .tag(item.id)
                }
                .listStyle(.sidebar)
                .accessibilityLabel("Software checked for vulnerabilities")
                .contentMargins(.top, 0, for: .scrollContent)
                .scrollContentBackground(.hidden)
            }
        }
        .background(UpkeepPalette.surface(in: colorScheme))
    }

    @ViewBuilder private var selectedDetail: some View {
        if let item = displayedInventory.first(where: { $0.id == selectedID }) {
            CVEAdvisoryDetail(item: item, result: resultsByID[item.id], pendingStatus: pendingStatus(item),
                              reviewUpdates: reviewUpdates, showSoftware: { showSoftware(item) })
        } else {
            WorkspaceEmptyState("Select software", systemImage: "shield",
                                   description: Text("Choose an item to review its advisories and fixed releases."))
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                securityTitle.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                securityActions
            }
            VStack(alignment: .leading, spacing: 12) {
                securityTitle
                securityActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, UpkeepLayout.pageInset)
        .padding(.vertical, 18)
    }

    private var securityTitle: some View {
        HStack(spacing: 14) {
            WorkspaceGlyph(systemImage: findings > 0 ? "exclamationmark.shield" : "shield.lefthalf.filled", size: 46,
                           color: findings > 0 ? UpkeepColors.warning(in: colorScheme) : nil)
            VStack(alignment: .leading, spacing: 5) {
                Text("CVE Checker")
                    .font(.system(size: 27, weight: .semibold))
                    .tracking(-0.85)
                    .accessibilityAddTraits(.isHeader)
                Text(securityStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var securityStatus: String {
        if state.running { return "Checking installed software…" }
        guard let checkedAt = state.checkedAt else { return "Find advisories for installed apps and packages." }
        let date = checkedAt.formatted(date: .abbreviated, time: .shortened)
        if checked == 0 { return "No checks completed · \(date)" }
        return "\(WorkspaceSummary.count(checked, "item", "items")) checked · \(date)"
    }

    private var securityActions: some View {
        let updateCount = store.cveBatchUpdateItems.count
        return HStack(spacing: 8) {
            if state.running {
                Button("Cancel Check") { state.cancel() }
                    .buttonStyle(.bordered)
            } else {
                Button(state.checkedAt == nil ? "Check CVEs" : "Check Again", systemImage: "arrow.clockwise") {
                    state.start(inventory: inventory, client: makeClient())
                }
                .buttonStyle(.bordered)
                .disabled(inventory.isEmpty)
            }
            Button(updateCount == 0 ? "Review Updates…" : "Review \(updateCount.formatted()) \(updateCount == 1 ? "Update" : "Updates")…",
                   systemImage: "arrow.down.circle") {
                batchReview = CVEBatchReview(items: store.cveBatchUpdateItems)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.running || updateCount == 0 || store.isWorking(.unifiedBatch))
            .help("Review affected software with available updates, including findings hidden by search or filters.")
            .accessibilityLabel("Update all affected software")
            .accessibilityValue("\(WorkspaceSummary.count(updateCount, "update", "updates")) available")
            .accessibilityHint("Opens a review before making changes, including findings hidden by the current filter.")
        }
        .fixedSize()
    }

    private var coverageSummary: some View {
        HStack(spacing: 8) {
            coverageMetric("All Software", value: items.count, filter: .all)
            coverageMetric("Findings", value: findings, filter: .findings)
            coverageMetric("Incomplete", value: incomplete, filter: .incomplete)
            coverageMetric("Not covered", value: uncovered, filter: .notCovered)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, UpkeepLayout.pageInset)
        .padding(.bottom, 13)
    }

    private func coverageMetric(_ title: String, value: Int, filter: CVEResultFilter) -> some View {
        let isSelected = state.filter == filter
        return Button { state.filter = filter } label: {
            HStack(spacing: 6) {
                Text(value, format: .number)
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .contentTransition(.numericText())
                    .upkeepAnimated(for: value, animation: UpkeepMotion.quick)
                Text(title)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .background(
                isSelected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(title)
        .accessibilityValue(WorkspaceSummary.count(value, "item", "items"))
        .upkeepAnimated(for: isSelected, animation: UpkeepMotion.quick)
    }
    private var searchField: some View {
        TextField("Filter software or CVE…", text: $state.searchText)
            .textFieldStyle(.roundedBorder).accessibilityLabel("Filter CVE results")
    }
    private var progress: some View {
        VStack(alignment: .leading, spacing: 7) {
            ProgressView(value: Double(state.results.count), total: Double(max(state.inventory.count, 1)))
            HStack {
                if let current = state.inventory.first(where: { $0.id == state.currentItemID }) {
                    Text("Checking \(current.name)…").lineLimit(1)
                }
                Spacer()
                Text("\(state.results.count) of \(state.inventory.count)").monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private var emptyTitle: String {
        if !search.isEmpty { return "No matching software" }
        switch state.filter {
        case .findings:
            if state.checkedAt == nil { return "Start a CVE check" }
            if !state.running && checked == 0 { return "No software checked" }
            return state.running ? "Checking for advisories" : "No advisories to show"
        case .incomplete: return "No incomplete checks"
        case .notCovered: return "No uncovered software"
        case .all: return "No software inventoried"
        }
    }
    private var emptyDescription: String {
        if !search.isEmpty { return "Try a software name or CVE identifier, or choose another filter." }
        switch state.filter {
        case .findings:
            if state.checkedAt == nil { return "Choose Check CVEs to check supported software in your inventory." }
            if !state.running && checked == 0 { return "Review incomplete checks and coverage, then check again." }
            return state.running ? "Matches will appear here as the check progresses."
                : "No known advisories were returned for checked items. Review coverage for software that was not checked."
        case .incomplete: return "Failed or cancelled checks will appear here."
        case .notCovered: return "Software without a supported identity or version will appear here."
        case .all: return "Refresh your app and package inventories before checking."
        }
    }
    private func pendingStatus(_ item: CVEInventoryItem) -> String {
        if item.target == nil { return "Not covered" }
        if state.currentItemID == item.id { return "Checking…" }
        return state.running ? "Waiting" : "Not checked"
    }
    private var coverageSheet: some View {
        VStack(spacing: 0) {
            WorkspaceSummary(
                title: "Coverage & Privacy",
                detail: "\(apps.count) apps · \(homebrew.count) Homebrew packages · \(packages.count) developer packages",
                systemImage: "checkmark.shield"
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    coverageSection("What Upkeep checks",
                        "OSV covers supported developer packages. Homebrew’s advisory feed covers core formulae. NVD covers mapped apps and casks. Unknown identities and unsupported versions are marked Not covered.")
                    coverageSection("What leaves your Mac",
                        "Requests include registry names or mapped product identities and installed versions. Local paths stay on your Mac. Upkeep matches Homebrew’s downloaded feed locally. NVD requests may take up to 45 seconds.")
                    coverageSection("How to read findings",
                        "NVD findings are potential matches. Check the source advisory for the affected platform and configuration. Severity comes from the source’s rating, such as CVSS. Unrated findings can still be serious, and a check with no findings cannot establish that software is safe.")
                    coverageSection("Fixed releases",
                        "Upkeep shows versions that OSV or Homebrew explicitly lists as fixed. NVD affected-version boundaries do not verify a fix. Check the advisory before choosing a release branch.")
                    coverageSection("When checks run",
                        "Automatic CVE checks follow launch and background update checks when enabled in Settings. Refresh update sources to include missing software. CVE checks only report findings.")
                }
                .padding(UpkeepLayout.pageInset)
            }
            WorkspaceDialogFooter {
                Spacer()
                Button("Done") { showingCoverage = false }
                    .keyboardShortcut(.defaultAction)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(width: 545, height: 490)
        .upkeepWorkspaceAppearance()
    }

    private func coverageSection(_ title: String, _ description: String) -> some View {
        InspectorSection(title: title) {
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
