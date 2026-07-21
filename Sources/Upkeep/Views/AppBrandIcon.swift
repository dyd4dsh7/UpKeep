import AppKit
import SwiftUI

enum AppBrand {
    static let image: NSImage = {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Upkeep") ?? NSImage()
    }()

    @MainActor static func applyApplicationIcon() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.applicationIconImage = image
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
    let size: CGFloat
    var body: some View {
        Image(nsImage: AppBrand.image)
            .resizable().scaledToFit().frame(width: size, height: size)
            .accessibilityLabel("Upkeep")
    }
}
