import AppKit
import SwiftUI

@main
struct UpkeepApp: App {
    @StateObject private var settings: AppSettings
    @UpkeepState private var store: UpkeepStore
    @StateObject private var updateViewState = UpdateViewState()

    init() {
        #if DEBUG
        if UIFixture.enabled {
            let defaults = UserDefaults(suiteName: "test.upkeep.ui-fixture.\(UUID().uuidString)")!
            defaults.set(true, forKey: "hasCompletedSetup")
            let appSettings = AppSettings(defaults: defaults)
            _settings = StateObject(wrappedValue: appSettings)
            _store = UpkeepState(initialValue: UIFixture.makeStore(settings: appSettings, operationState: UIFixture.operationState))
            return
        }
        #endif
        let appSettings = AppSettings()
        _settings = StateObject(wrappedValue: appSettings)
        _store = UpkeepState(initialValue: UpkeepStore(settings: appSettings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.upkeepStoreReference, store)
                .environmentObject(settings)
                .environmentObject(updateViewState)
                .frame(minWidth: 760, minHeight: 500)
                .onAppear {
                    #if DEBUG
                    // Isolated visual QA; never changes the user's system appearance.
                    if UIFixture.enabled {
                        if ProcessInfo.processInfo.arguments.contains("--ui-fixture-light") {
                            NSApp.appearance = NSAppearance(named: .aqua)
                        } else if ProcessInfo.processInfo.arguments.contains("--ui-fixture-dark") {
                            NSApp.appearance = NSAppearance(named: .darkAqua)
                        }
                    }
                    #endif
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: initialWindowSize.width, height: initialWindowSize.height)
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
            SettingsView().environmentObject(settings)
                .environment(\.upkeepStoreReference, store)
        }
    }

    private var initialWindowSize: CGSize {
        #if DEBUG
        if UIFixture.enabled && ProcessInfo.processInfo.arguments.contains("--ui-fixture-narrow") {
            return CGSize(width: 760, height: 500)
        }
        #endif
        return CGSize(width: 1180, height: 720)
    }
}
