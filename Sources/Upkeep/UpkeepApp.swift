import AppKit
import SwiftUI

@main
struct UpkeepApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var store: UpkeepStore

    init() {
        let appSettings = AppSettings()
        _settings = StateObject(wrappedValue: appSettings)
        _store = StateObject(wrappedValue: UpkeepStore(settings: appSettings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink { Text("Settings…") }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates") { Task { await store.scan() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(store.isScanning)
            }
        }

        MenuBarExtra {
            Button("Open Upkeep") { store.openMainWindow() }
            Button("Check for Updates") { Task { await store.scan() } }
                .disabled(store.isScanning)
            Divider()
            Text(store.totalUpdateCount == 0 ? "Everything is current" : "\(store.totalUpdateCount) updates available")
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Upkeep") { NSApplication.shared.terminate(nil) }
        } label: {
            HStack(spacing: 3) {
                AppBrandIcon(size: 16)
                if settings.showMenuBarCount { Text("\(store.totalUpdateCount)").monospacedDigit() }
            }
            .help(store.totalUpdateCount == 0 ? "Upkeep: no updates available" : "Upkeep: \(store.totalUpdateCount) updates available")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView().environmentObject(settings).environmentObject(store)
        }
    }
}
