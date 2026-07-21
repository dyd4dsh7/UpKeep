import AppKit

@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private weak var store: UpkeepStore?
    private var countItem: NSMenuItem?

    func configure(store: UpkeepStore, settings: AppSettings) {
        self.store = store
        refresh(
            updateCount: store.totalUpdateCount,
            showCount: settings.showMenuBarCount,
            isVisible: settings.showMenuBarItem
        )
    }

    func refresh(updateCount: Int, showCount: Bool, isVisible: Bool) {
        guard isVisible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            countItem = nil
            return
        }

        if statusItem == nil { createStatusItem() }
        guard let item = statusItem, let button = item.button else { return }

        let icon = NSImage(
            systemSymbolName: updateCount == 0 ? "checkmark.circle.fill" : "arrow.down.circle.fill",
            accessibilityDescription: "Upkeep"
        )
        icon?.isTemplate = true
        button.image = icon
        button.imagePosition = .imageLeading
        button.title = showCount ? " \(updateCount)" : ""
        button.toolTip = updateCount == 0
            ? "Upkeep — no updates available"
            : "Upkeep — \(updateCount) updates available"
        button.setAccessibilityLabel(button.toolTip)
        countItem?.title = updateCount == 0
            ? "Everything is current"
            : "\(updateCount) update\(updateCount == 1 ? "" : "s") available"
        item.length = NSStatusItem.variableLength
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Upkeep", action: #selector(openUpkeep), keyEquivalent: "")
        menu.addItem(withTitle: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        let count = NSMenuItem(title: "Everything is current", action: nil, keyEquivalent: "")
        count.isEnabled = false
        menu.addItem(count)
        countItem = count
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
