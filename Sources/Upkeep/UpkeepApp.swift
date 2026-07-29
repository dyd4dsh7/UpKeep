import AppKit
import SwiftUI

@main
struct UpkeepApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var store: UpkeepStore
    @StateObject private var updateViewState = UpdateViewState()

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
                .environmentObject(updateViewState)
                .frame(minWidth: 760, minHeight: 500)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1180, height: 720)
        .commands {
            InspectorCommands()
            CommandMenu("Updates") {
                Button("Check for Updates") {
                    Task { await store.scan() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isScanning)

                Button("Show Updates") {
                    store.searchText = ""
                    store.selection = .updates
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Menu("Filter Updates") {
                    ForEach(UpdateListFilter.allCases) { filter in
                        Button {
                            store.searchText = ""
                            store.selection = .updates
                            updateViewState.filter = filter
                        } label: {
                            if updateViewState.filter == filter {
                                Label(filter.rawValue, systemImage: "checkmark")
                            } else {
                                Text(filter.rawValue)
                            }
                        }
                    }
                }

                Divider()

                Button("Review All Updates…") {
                    store.searchText = ""
                    store.selection = .updates
                    store.isShowingBatchReview = true
                }
                .keyboardShortcut("u", modifiers: [.command, .option])
                .disabled(store.availableBatchUpdateItems.isEmpty)
            }
        }

        Settings {
            SettingsView().environmentObject(settings).environmentObject(store)
        }
    }
}
