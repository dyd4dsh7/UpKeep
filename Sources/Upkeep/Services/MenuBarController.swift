import AppKit

@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private weak var store: UpkeepStore?
    private var countItem: NSMenuItem?
    private var lastCheckItem: NSMenuItem?
    private var checkActionItem: NSMenuItem?

    func configure(store: UpkeepStore, settings: AppSettings) {
        self.store = store
        refresh(
            updateCount: store.totalUpdateCount,
            showCount: settings.showMenuBarCount,
            isVisible: settings.showMenuBarItem,
            state: store.updateCheckState,
            lastChecked: store.lastChecked
        )
    }

    func refresh(updateCount: Int, showCount: Bool, isVisible: Bool, state: UpdateCheckState, lastChecked: Date?) {
        guard isVisible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            countItem = nil
            lastCheckItem = nil
            checkActionItem = nil
            return
        }

        if statusItem == nil { createStatusItem() }
        guard let item = statusItem, let button = item.button else { return }

        let health = MenuBarHealth(count: updateCount, state: state, lastChecked: lastChecked)
        let icon = NSImage(
            systemSymbolName: health.symbol,
            accessibilityDescription: "Upkeep"
        )
        icon?.isTemplate = true
        button.image = icon
        button.imagePosition = .imageLeading
        button.title = showCount ? " \(updateCount)" : ""
        button.toolTip = health.tooltip
        button.setAccessibilityLabel(button.toolTip)
        countItem?.title = health.summary
        lastCheckItem?.isHidden = lastChecked == nil
        if let lastChecked {
            lastCheckItem?.title = "Last checked \(lastChecked.formatted(date: .abbreviated, time: .shortened))"
        }
        checkActionItem?.title = state == .checking ? "Checking for Updates…" : "Check for Updates"
        checkActionItem?.isEnabled = state != .checking
        item.length = NSStatusItem.variableLength
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        let count = NSMenuItem(title: "Upkeep", action: nil, keyEquivalent: "")
        count.isEnabled = false
        menu.addItem(count)
        countItem = count
        let lastCheck = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        lastCheck.isEnabled = false
        lastCheck.isHidden = true
        menu.addItem(lastCheck)
        lastCheckItem = lastCheck
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Upkeep", action: #selector(openUpkeep), keyEquivalent: "")
        checkActionItem = menu.addItem(withTitle: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Upkeep", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != nil { menuItem.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func openUpkeep() { store?.openMainWindow() }

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
