import AppKit
import SwiftUI

enum AppBrand {
    static let image: NSImage = {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Upkeep") ?? NSImage()
    }()

    @MainActor static func applyApplicationIcon() {
        NSApplication.shared.applicationIconImage = image
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
