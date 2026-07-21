import SwiftUI

struct ChangelogView: View {
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: "Changelog",
                subtitle: "What’s new in Upkeep",
                systemImage: "list.bullet.rectangle.fill"
            )
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(UpkeepRelease.all) { release in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Upkeep \(release.version)").font(.title2.bold())
                                if release.version == UpkeepRelease.all.first?.version {
                                    Text("CURRENT").font(.caption2.bold()).foregroundStyle(.blue)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(.blue.opacity(0.12), in: Capsule())
                                }
                                Spacer()
                                Text(release.date).foregroundStyle(.secondary)
                            }
                            ForEach(release.changes, id: \.self) { change in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).padding(.top, 2)
                                    Text(change).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(20)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(24).frame(maxWidth: 850)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct UpkeepRelease: Identifiable {
    var id: String { version }
    let version: String
    let date: String
    let changes: [String]

    static let all = [
        UpkeepRelease(version: "0.6.0", date: "21 July 2026", changes: [
            "Added bundled package-manager artwork for Homebrew, npm, pnpm, Python, RubyGems, and Cargo.",
            "Made installed apps and developer packages clickable with complete detail views.",
            "Added explicit version installation for npm, pnpm, pip, RubyGems, and Cargo packages.",
            "Added this in-app changelog and the project’s private GitHub repository history."
        ]),
        UpkeepRelease(version: "0.5.0", date: "21 July 2026", changes: [
            "Added installed-only npm, pnpm, Python/pip, RubyGems, and Cargo sections.",
            "Kept current developer packages visible and included outdated packages in the update count.",
            "Counted newer Homebrew casks for matching unmanaged apps."
        ]),
        UpkeepRelease(version: "0.4.0", date: "21 July 2026", changes: [
            "Added macOS stable updates, beta enrollment, and compatible full-installer discovery.",
            "Added update history, pre-update app backups, and direct app rollback where supported.",
            "Added recovery guidance for package and macOS updates that cannot be reverted automatically."
        ]),
        UpkeepRelease(version: "0.3.0", date: "21 July 2026", changes: [
            "Added Homebrew formula and cask inventory, filters, package details, and batch updates.",
            "Added Homebrew adoption for compatible apps and dependency visibility."
        ]),
        UpkeepRelease(version: "0.2.0", date: "21 July 2026", changes: [
            "Added GitHub Releases and Electron metadata checking.",
            "Added source filters, update counters, and automatic checking on app launch."
        ]),
        UpkeepRelease(version: "0.1.0", date: "21 July 2026", changes: [
            "Created the native SwiftUI macOS app scanner.",
            "Added Mac App Store and Sparkle update discovery."
        ])
    ]
}
