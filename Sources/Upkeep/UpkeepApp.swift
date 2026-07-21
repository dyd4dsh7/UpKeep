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
                .frame(minWidth: 1000, minHeight: 560)
        }
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            SettingsView().environmentObject(settings).environmentObject(store)
        }
    }
}
