import SwiftUI

/// "What's New" for a Homebrew or developer package, from its GitHub releases.
struct PackageReleaseNotesSection: View {
    let notes: PackageReleaseNotes
    @State private var showsAll = false

    var body: some View {
        InspectorSection(title: "What’s New") {
            Text("Version \(notes.version)")
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                ReleaseNotesText(notes: notes.notes, showsAll: $showsAll)
                if let url = notes.url {
                    Link("Open Release on GitHub", destination: url)
                        .font(.callout)
                }
            }
        }
    }
}

/// Release notes loaded for one package version. Panels load them from a view
/// that is always shown, because an empty section never starts its own task.
struct LoadedReleaseNotes: Equatable {
    var key: String?
    var notes: PackageReleaseNotes?

    func notes(for key: String) -> PackageReleaseNotes? { self.key == key ? notes : nil }
}
