import AppKit
import SwiftUI

struct IntelAppBadge: View {
    var body: some View {
        Label("Intel app", systemImage: "exclamationmark.triangle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .fixedSize()
            .help("This app has no Apple Silicon executable. Open its details to review migration options.")
    }
}

struct AppleSiliconMigrationWarning: View {
    let showGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Intel app on an Apple Silicon Mac", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("This installation has no native Apple Silicon executable. Check whether the developer offers an Apple Silicon or Universal edition.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Move to Apple Silicon…", action: showGuide)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .upkeepOutlinedInspectorCard()
    }
}

struct AppleSiliconMigrationView: View {
    @UpkeepStoreReference private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @StateObject private var state = AppleSiliconMigrationState()
    let app: InstalledApp

    private var source: AppleSiliconMigrationSource {
        .resolve(app: app, homebrewToken: store.homebrewPackage(for: app)?.token)
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceSummary(title: "Move to Apple Silicon", detail: app.name, systemImage: "cpu") {
                AppIcon(url: app.url, size: 38)
                    .accessibilityHidden(true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    step("1. Find a native edition", text: sourceInstructions) {
                        sourceButton
                        if state.openingFailed {
                            Label("The source could not be opened. Try the developer’s website.", systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(UpkeepColors.warning(in: scheme))
                        }
                    }
                    step("2. Install the replacement", text: installInstructions) {
                        Text(app.url.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Show Installed App in Finder", systemImage: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([app.url])
                        }
                    }
                    step("3. Verify Apple Silicon support", text: "After installation, check the replacement app. Upkeep verifies its executable even when the version number stays the same.") {
                        if let verification = state.verification {
                            Label(verification.message, systemImage: verification == .native ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(verification == .native ? UpkeepPalette.accent(in: scheme) : UpkeepColors.warning(in: scheme))
                                .font(.callout.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("appleSiliconVerification")
                        }
                    }
                }
                .padding(UpkeepLayout.pageInset)
            }

            WorkspaceDialogFooter {
                Button(state.verification == .native ? "Done" : "Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    state.isChecking = true
                    Task {
                        state.verification = await store.verifyAppleSiliconMigration(app)
                        state.isChecking = false
                    }
                } label: {
                    WorkingActionLabel(isWorking: state.isChecking, idleTitle: "Verify Installed App", workingTitle: "Checking…")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isChecking)
            }
        }
        .frame(width: 540, height: 500)
        .upkeepWorkspaceAppearance()
    }

    private func step<Actions: View>(_ title: String, text: String, @ViewBuilder actions: () -> Actions) -> some View {
        InspectorSection(title: title) {
            VStack(alignment: .leading, spacing: 9) {
                Text(text).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
            }
        }
    }

    private var sourceInstructions: String {
        switch source {
        case .updateManager:
            "Check \(app.updateManagement.rawValue) for an Apple Silicon or Universal edition. Availability depends on the developer; a normal update may still be Intel-only."
        case .homebrew:
            "Review this Homebrew cask for Apple Silicon support. A current version number alone does not confirm that the installed app is native."
        case .releases:
            "Look for a macOS download marked Apple Silicon, ARM64, AArch64, or Universal in the developer’s releases. Upkeep has not verified that a native edition is available."
        case .builtInUpdater:
            "Open the app’s update menu or developer website and look for an Apple Silicon or Universal edition. Its updater may continue offering Intel builds."
        case .developerWebsite:
            "Upkeep has no known download source for this app. Visit the developer’s official website and look for an Apple Silicon or Universal edition. If none is offered, migration is not available yet."
        }
    }

    private var installInstructions: String {
        switch source {
        case .updateManager:
            "Save your work and quit the app. Use \(app.updateManagement.rawValue) to install the native edition, keeping the same app location."
        case .homebrew:
            "Save your work and quit the app. Use an Apple Silicon installation of Homebrew to reinstall this cask. Keep this app managed by Homebrew."
        default:
            "Save your work and quit the app. Follow the developer’s installation instructions to replace the Intel copy at the location below with the Apple Silicon or Universal edition."
        }
    }

    @ViewBuilder private var sourceButton: some View {
        switch source {
        case .updateManager:
            Button(app.updateManagement.actionTitle) { store.openUpdateManager(for: app) }
        case let .homebrew(url):
            Button("Review Homebrew Cask") { state.openingFailed = !NSWorkspace.shared.open(url) }
        case let .releases(url):
            Button("Open Developer Releases") { state.openingFailed = !NSWorkspace.shared.open(url) }
        case .builtInUpdater:
            Button("Open App") { state.openingFailed = !NSWorkspace.shared.open(app.url) }
        case .developerWebsite:
            EmptyView()
        }
    }
}

@MainActor
private final class AppleSiliconMigrationState: ObservableObject {
    @Published var isChecking = false
    @Published var verification: AppleSiliconVerification?
    @Published var openingFailed = false
}
