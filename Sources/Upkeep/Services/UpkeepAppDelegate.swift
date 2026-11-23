import AppKit
import SwiftUI
import UserNotifications

/// The single main window (`Window(id: "main")`). Opening goes through SwiftUI's
/// `openWindow`, which recreates the window after it was closed and brings an
/// existing one forward instead of creating a second copy.
/// Buttons on the "Upkeep found updates" notification.
enum UpdateNotificationAction: String {
    case review = "upkeep.review"
    case updateRecommended = "upkeep.update-recommended"

    static let categoryIdentifier = "upkeep.updates"

    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [
                UNNotificationAction(identifier: review.rawValue, title: "Review", options: [.foreground]),
                UNNotificationAction(identifier: updateRecommended.rawValue, title: "Update Recommended", options: [])
            ],
            intentIdentifiers: []
        )
    }
}

@MainActor
enum MainWindow {
    static let id = "main"
    /// Captured from a view in the scene; the action stays valid after that view closes.
    static var openAction: OpenWindowAction?

    static var window: NSWindow? {
        NSApplication.shared.windows.first { $0.identifier?.rawValue == id }
    }

    static var isVisible: Bool { window?.isVisible == true }

    static func open() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let openAction {
            openAction(id: id)
        } else {
            window?.makeKeyAndOrderFront(nil)
        }
    }

    /// `.searchable` does not bind ⌘F by itself, so the Find command focuses
    /// the toolbar search field through AppKit.
    static func focusSearch() {
        if !isVisible || NSApplication.shared.keyWindow !== window { open() }
        DispatchQueue.main.async {
            guard let window,
                  let search = window.toolbar?.items.lazy.compactMap({ $0 as? NSSearchToolbarItem }).first
            else { return }
            window.makeKeyAndOrderFront(nil)
            search.beginSearchInteraction()
        }
    }
}

@MainActor
final class UpkeepAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by `UpkeepApp.init`, before AppKit finishes launching.
    static var store: UpkeepStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let store = Self.store {
            MenuBarController.shared.configure(store: store, settings: store.settings)
        }
        // UserNotifications requires a bundled app; unbundled debug runs skip it.
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            UNUserNotificationCenter.current().setNotificationCategories([UpdateNotificationAction.category])
        }
    }

    /// `upkeep://` links; see `UpkeepLink`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let link = UpkeepLink(url) else {
                DiagnosticsStore.shared.record(.warning, category: .command, "Unrecognized Upkeep link", metadata: ["Link": url.absoluteString])
                continue
            }
            Self.store?.open(link)
        }
    }

    /// Upkeep keeps running for the menu bar item and background checks.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !MainWindow.isVisible { MainWindow.open() }
        return false
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        await MainActor.run {
            guard let store = Self.store else { return }
            switch action {
            case UpdateNotificationAction.review.rawValue:
                store.showBatchReview()
            case UpdateNotificationAction.updateRecommended.rawValue:
                Task { await store.updateRecommendedFromNotification() }
            default:
                store.showUpdates()
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            // Skip the banner when the Updates page is already in front.
            let showingUpdates = NSApp.isActive && MainWindow.window?.isKeyWindow == true
                && Self.store?.selection == .updates
            return showingUpdates ? [.list] : [.banner, .list, .sound]
        }
    }
}
