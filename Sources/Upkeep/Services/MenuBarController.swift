import AppKit
import Combine

/// Owns the menu bar item and Dock badge. Both follow store and settings
/// changes directly, so they stay current while the main window is closed.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()
    static let pendingUpdateLimit = 10

    struct Presentation: Equatable {
        let updateCount: Int
        let showCount: Bool
        let isVisible: Bool
        let state: UpdateCheckState
        let lastChecked: Date?
    }

    private var statusItem: NSStatusItem?
    private weak var store: UpkeepStore?
    private var observers = Set<AnyCancellable>()
    private var isRefreshScheduled = false
    private var appliedPresentation: Presentation?
    private var pendingTargets: [PendingUpdateTarget] = []

    func configure(store: UpkeepStore, settings: AppSettings) {
        guard self.store !== store else { return }
        self.store = store
        observers.removeAll()
        // The store publishes once after each change phase; settings publish
        // before each assignment. Coalesce both into one refresh per run loop.
        store.objectWillChange
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &observers)
        settings.objectWillChange
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &observers)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshDock(force: true) }
            .store(in: &observers)
        refresh()
        refreshDock(force: true)
    }

    private func scheduleRefresh() {
        guard !isRefreshScheduled else { return }
        isRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isRefreshScheduled = false
            refresh()
        }
    }

    /// Applies the current state; unchanged state does no AppKit work.
    func refresh() {
        guard let store else { return }
        let settings = store.settings
        refreshDock(force: false)
        let presentation = Presentation(
            updateCount: store.totalUpdateCount,
            showCount: settings.showMenuBarCount,
            isVisible: settings.showMenuBarItem,
            state: store.updateCheckState,
            lastChecked: store.lastChecked
        )
        guard presentation != appliedPresentation else { return }
        appliedPresentation = presentation
        apply(presentation)
    }

    private func refreshDock(force: Bool) {
        guard let store else { return }
        let count = store.settings.showDockBadge ? store.totalUpdateCount : 0
        if force {
            AppBrand.applyDockPresentation(updateCount: count)
        } else {
            AppBrand.refreshDockPresentationIfNeeded(updateCount: count)
        }
    }

    private func apply(_ presentation: Presentation) {
        guard presentation.isVisible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }

        if statusItem == nil { createStatusItem() }
        guard let item = statusItem, let button = item.button else { return }

        let health = MenuBarHealth(count: presentation.updateCount, state: presentation.state,
                                   lastChecked: presentation.lastChecked)
        let icon = NSImage(systemSymbolName: health.symbol, accessibilityDescription: "Upkeep")
        icon?.isTemplate = true
        button.image = icon
        button.imagePosition = .imageLeading
        button.title = Self.buttonTitle(count: presentation.updateCount, showCount: presentation.showCount)
        button.toolTip = health.tooltip
        button.setAccessibilityLabel(health.tooltip)
        item.length = NSStatusItem.variableLength
    }

    /// Icon only at zero, so the item never reads " 0".
    nonisolated static func buttonTitle(count: Int, showCount: Bool) -> String {
        showCount && count > 0 ? " \(count)" : ""
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menuNeedsUpdate(menu)
        item.menu = menu
        statusItem = item
    }

    /// Rebuilt each time the menu opens, so it always lists current updates.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        pendingTargets = []
        guard let store else { return }

        let health = MenuBarHealth(count: store.totalUpdateCount, state: store.updateCheckState,
                                   lastChecked: store.lastChecked)
        let summary = NSMenuItem(title: health.summary, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        if let lastChecked = store.lastChecked {
            let checked = NSMenuItem(
                title: "Last checked \(lastChecked.formatted(date: .abbreviated, time: .shortened))",
                action: nil, keyEquivalent: ""
            )
            checked.isEnabled = false
            menu.addItem(checked)
        }

        let pending = store.pendingUpdateSummaries
        if !pending.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Pending Updates"))
            for (index, update) in pending.prefix(Self.pendingUpdateLimit).enumerated() {
                let entry = NSMenuItem(title: update.name, action: #selector(showPendingUpdate(_:)), keyEquivalent: "")
                entry.tag = index
                entry.toolTip = "Show \(update.name) in Upkeep"
                if #available(macOS 14.4, *) {
                    entry.subtitle = update.versionText
                } else {
                    entry.title = "\(update.name)  \(update.versionText)"
                }
                pendingTargets.append(update.target)
                menu.addItem(entry)
            }
            if pending.count > Self.pendingUpdateLimit {
                let more = pending.count - Self.pendingUpdateLimit
                menu.addItem(NSMenuItem(title: "\(more.formatted()) More…", action: #selector(showUpdates), keyEquivalent: ""))
            }
        }
        if !store.availableBatchUpdateItems.isEmpty {
            menu.addItem(.separator())
            let review = NSMenuItem(title: "Update All Recommended…", action: #selector(reviewUpdates), keyEquivalent: "")
            review.isEnabled = !store.isWorking(.unifiedBatch)
            menu.addItem(review)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Upkeep", action: #selector(openUpkeep), keyEquivalent: ""))
        let checking = store.updateCheckState == .checking
        let check = NSMenuItem(title: checking ? "Checking for Updates…" : "Check for Updates",
                               action: #selector(checkForUpdates), keyEquivalent: "")
        check.isEnabled = !checking
        menu.addItem(check)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Upkeep", action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items where menuItem.action != nil { menuItem.target = self }
    }

    @objc private func openUpkeep() { store?.openMainWindow() }

    @objc private func showUpdates() { store?.showUpdates() }

    @objc private func reviewUpdates() { store?.showBatchReview() }

    @objc private func showPendingUpdate(_ sender: NSMenuItem) {
        guard pendingTargets.indices.contains(sender.tag) else { return }
        store?.revealPendingUpdate(pendingTargets[sender.tag])
    }

    @objc private func checkForUpdates() {
        guard let store else { return }
        Task { await store.scan() }
    }

    @objc private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if !NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            _ = NSApplication.shared.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
