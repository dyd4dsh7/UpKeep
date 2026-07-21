import SwiftUI

@main
struct UpkeepApp: App {
    @StateObject private var store = UpkeepStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates") {
                    Task { await store.scan() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isScanning)
            }
        }
    }
}
