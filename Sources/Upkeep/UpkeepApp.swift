import AppKit
import SwiftUI

@main
struct UpkeepApp: App {
    @NSApplicationDelegateAdaptor(UpkeepAppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @UpkeepState private var store: UpkeepStore
    @StateObject private var updateViewState = UpdateViewState()

    init() {
        #if DEBUG
        if UIFixture.enabled {
            let defaults = UserDefaults(suiteName: "test.upkeep.ui-fixture.\(UUID().uuidString)")!
            let showSetup = ProcessInfo.processInfo.arguments.contains("--ui-fixture-setup")
            defaults.set(!showSetup, forKey: "hasCompletedSetup")
            let appSettings = AppSettings(defaults: defaults)
            if !showSetup, UIFixture.operationState == .workspace {
                appSettings.completeSetup(.advanced, sidebarViewMode: .advanced)
            }
            _settings = StateObject(wrappedValue: appSettings)
            let fixtureStore = UIFixture.makeStore(settings: appSettings, operationState: UIFixture.operationState)
            if let route = UIFixture.route { fixtureStore.navigation.selection = route }
            if let section = UIFixture.settingsSection { appSettings.selectedSection = section }
            if ProcessInfo.processInfo.arguments.contains("--ui-fixture-self-update") {
                SelfUpdateController.shared.showFixtureRelease()
            }
            UpkeepAppDelegate.store = fixtureStore
            _store = UpkeepState(initialValue: fixtureStore)
            return
        }
        #endif
        let appSettings = AppSettings()
        _settings = StateObject(wrappedValue: appSettings)
        let appStore = UpkeepStore(settings: appSettings)
        UpkeepAppDelegate.store = appStore
        _store = UpkeepState(initialValue: appStore)
    }

    var body: some Scene {
        // One main window: closing it keeps Upkeep running, and every "open"
        // path (menu bar, Dock, notification) reuses or recreates this window.
        Window("Upkeep", id: MainWindow.id) {
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
                        if UIFixture.showsBatchReview {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { store.isShowingBatchReview = true }
                        }
                    }
                    #endif
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: initialWindowSize.width, height: initialWindowSize.height)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Upkeep Updates…") {
                    Task { await SelfUpdateController.shared.check(userInitiated: true) }
                }
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") { MainWindow.focusSearch() }
                    .keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("Hide Details") { store.clearInspectorSelection() }
                    .keyboardShortcut("i", modifiers: [.command, .control])
                    .disabled(!store.hasInspectorSelection)
            }
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
        if UIFixture.enabled, let width = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--ui-fixture-width=") })
            .flatMap({ Double($0.dropFirst("--ui-fixture-width=".count)) }) {
            return CGSize(width: width, height: 720)
        }
        #endif
        return CGSize(width: 1180, height: 720)
    }
}
