import AppKit
import SwiftUI

enum AppBrand {
    private static let lightImage = loadImage(named: "AppIcon")
    private static let darkImage = loadImage(named: "AppIconDark")

    private static func loadImage(named name: String) -> NSImage {
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Upkeep") ?? NSImage()
    }

    static func image(for colorScheme: ColorScheme) -> NSImage {
        colorScheme == .dark ? darkImage : lightImage
    }

    @MainActor static func applyApplicationIcon(for colorScheme: ColorScheme) {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.applicationIconImage = image(for: colorScheme)
        application.dockTile.display()
    }

    @MainActor static func applyDockBadge(updateCount: Int) {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.dockTile.contentView = nil
        application.dockTile.badgeLabel = updateCount > 0 ? String(updateCount) : nil
        application.dockTile.display()
    }
}

struct AppBrandIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let size: CGFloat

    var body: some View {
        Image(nsImage: AppBrand.image(for: colorScheme))
            .resizable().scaledToFit().frame(width: size, height: size)
            .accessibilityLabel("Upkeep")
    }
}
