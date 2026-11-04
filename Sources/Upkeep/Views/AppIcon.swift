import AppKit
import SwiftUI

struct AppIcon: View {
    let url: URL
    let size: CGFloat
    @UpkeepState private var image: NSImage?

    var body: some View {
        let identity = AppIconIdentity(url: url)
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "app").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: identity) { image = AppIconCache.shared.image(for: identity) }
    }
}
