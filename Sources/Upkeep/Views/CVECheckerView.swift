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
            header.padding(.horizontal, 22).padding(.vertical, 18)
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
            Divider()
            coverageSummary.padding(.horizontal, 18).padding(.vertical, 10).background(.bar)
        }
        .onChange(of: displayedInventory.map(\.id), initial: true) { _, ids in
            if selectedID == nil || !ids.contains(selectedID ?? "") { selectedID = ids.first }
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
                Picker("Show", selection: $state.filter) {
                    ForEach(CVEResultFilter.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).labelsHidden().fixedSize()
                .accessibilityLabel("Filter software by result")
            }.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
            searchField.padding(.horizontal, 14).padding(.bottom, 12)
            if displayedInventory.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: search.isEmpty ? "shield" : "magnifyingglass",
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
        }.background(.quaternary.opacity(0.12))
    }

    @ViewBuilder private var selectedDetail: some View {
        if let item = displayedInventory.first(where: { $0.id == selectedID }) {
            CVEAdvisoryDetail(item: item, result: resultsByID[item.id], pendingStatus: pendingStatus(item),
                              reviewUpdates: reviewUpdates, showSoftware: { showSoftware(item) })
        } else {
            ContentUnavailableView("Select software", systemImage: "shield",
                                   description: Text("Choose an item to review its advisories and fixed releases."))
        }
    }

    private var header: some View {
        let updateCount = store.cveBatchUpdateItems.count
        return HStack(alignment: .center, spacing: 16) {
            Image(systemName: findings > 0 ? "exclamationmark.shield" : "shield")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(findings > 0 ? CVEColors.severity(.medium, in: colorScheme) : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(state.running ? "Checking your software" : state.checkedAt == nil ? "Check your software"
                     : findings == 0 ? "No advisories returned" : "\(findings) \(findings == 1 ? "item needs" : "items need") review")
                    .font(.title2.weight(.semibold))
                if let checkedAt = state.checkedAt {
                    Text("\(state.running ? "Checking" : "Last checked") \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Find published advisories for installed apps and packages.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Button("Update All…") {
                    batchReview = CVEBatchReview(items: store.cveBatchUpdateItems)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.running || updateCount == 0 || store.isWorking(.unifiedBatch))
                .help("Review all affected software with available updates, including findings hidden by search or filters.")
                .accessibilityLabel("Update all affected software")
                .accessibilityValue("\(updateCount) \(updateCount == 1 ? "update" : "updates") available")
                .accessibilityHint(state.running ? "Available after the CVE check finishes." : "Opens a review before making changes, including findings hidden by the current filter.")
                Text("\(updateCount) \(updateCount == 1 ? "update" : "updates") available")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var coverageSummary: some View {
        HStack(spacing: 18) {
            coverageMetric("Checked", value: checked, filter: .all)
            coverageMetric("Incomplete", value: incomplete, filter: .incomplete)
            coverageMetric("Not covered", value: uncovered, filter: .notCovered)
            Spacer(minLength: 0)
            if state.running {
                Button("Cancel Check") { state.cancel() }
            } else {
                Button(state.checkedAt == nil ? "Check CVEs" : "Check Again", systemImage: "arrow.clockwise") {
                    state.start(inventory: inventory, client: makeClient())
                }.disabled(inventory.isEmpty)
            }
        }.font(.callout)
    }
    private func coverageMetric(_ title: String, value: Int, filter: CVEResultFilter) -> some View {
        Button { state.filter = filter } label: {
            Text("\(value) \(title.lowercased())").foregroundStyle(.secondary)
        }.buttonStyle(.plain)
        .accessibilityLabel("\(title): \(value). Show \(filter.rawValue.lowercased())")
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
        VStack(alignment: .leading, spacing: 18) {
            Text("Coverage & privacy").font(.title2.weight(.semibold))
            Text("\(apps.count) apps · \(homebrew.count) Homebrew · \(packages.count) developer packages")
                .font(.callout).foregroundStyle(.secondary)
            Text("Checks use OSV for developer packages, Homebrew’s advisory feed for core formulae, and NVD for mapped apps and casks. Unknown identities and unsupported versions remain not covered.")
            Text("NVD findings are potential matches. Review the linked records for platform and configuration applicability. No matches does not guarantee safety.")
            Text("Registry names or mapped product identities and installed versions are sent to these services. Local paths stay on your Mac. Homebrew’s shared feed is matched locally. NVD requests are paced and a response can take up to 45 seconds.")
            Text("Severity reflects source ratings, using CVSS base scores when available. Unrated does not mean low risk. Fixed releases come from explicit OSV or Homebrew fixed events for the matched package; NVD affected-range boundaries are not treated as verified fixes. Fixes may span release branches and do not imply every later version is unaffected.")
            Text("Automatic CVE checks follow launch and background update refreshes when enabled in Settings. Results use the current inventory. Refresh update sources to include missing software. Checks do not install updates.")
            HStack { Spacer(); Button("Done") { showingCoverage = false }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 480)
    }
}
