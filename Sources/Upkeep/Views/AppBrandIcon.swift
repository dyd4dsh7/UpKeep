import AppKit
import SwiftUI

enum AppBrand {
    @MainActor private static let dockTileView = UpkeepDockTileView()
    @MainActor private static var appliedDockTheme: String?
    @MainActor private static var appliedUpdateCount: Int?
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

    static var currentIconAppearanceTheme: String {
        UserDefaults.standard.string(forKey: "AppleIconAppearanceTheme") ?? "Default"
    }

    private static var dockImage: NSImage {
        currentIconAppearanceTheme.localizedCaseInsensitiveContains("dark")
            ? darkImage
            : lightImage
    }

    @MainActor static func applyDockPresentation(updateCount: Int) {
        applyDockPresentation(updateCount: updateCount, force: true)
    }

    @MainActor static func refreshDockPresentationIfNeeded(updateCount: Int) {
        applyDockPresentation(updateCount: updateCount, force: false)
    }

    @MainActor private static func applyDockPresentation(updateCount: Int, force: Bool) {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let theme = currentIconAppearanceTheme
        guard force || appliedDockTheme != theme || appliedUpdateCount != updateCount else { return }

        // This SwiftPM bundle cannot run Xcode's Icon Composer build phase, so
        // keep its Dock presentation synchronized with macOS at runtime.
        let icon = dockImage
        application.applicationIconImage = icon
        dockTileView.icon = icon
        dockTileView.updateCount = updateCount
        application.dockTile.badgeLabel = nil
        application.dockTile.contentView = dockTileView
        application.dockTile.display()
        appliedDockTheme = theme
        appliedUpdateCount = updateCount
    }
}

private final class UpkeepDockTileView: NSView {
    var icon = NSImage() {
        didSet { needsDisplay = true }
    }

    var updateCount = 0 {
        didSet { needsDisplay = true }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        icon.draw(
            in: bounds.insetBy(dx: bounds.width * 0.025, dy: bounds.height * 0.025),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        guard updateCount > 0 else { return }

        let label = updateCount > 999 ? "999+" : String(updateCount)
        let badgeHeight = bounds.height * 0.39
        let font = NSFont.systemFont(ofSize: badgeHeight * 0.52, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = label.size(withAttributes: attributes)
        let badgeWidth = max(badgeHeight, textSize.width + badgeHeight * 0.42)
        let badgeRect = NSRect(
            x: bounds.maxX - badgeWidth,
            y: bounds.maxY - badgeHeight,
            width: badgeWidth,
            height: badgeHeight
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.shadowBlurRadius = bounds.height * 0.025
        shadow.shadowOffset = NSSize(width: 0, height: -bounds.height * 0.012)
        shadow.set()
        NSColor.systemRed.setFill()
        NSBezierPath(
            roundedRect: badgeRect,
            xRadius: badgeHeight / 2,
            yRadius: badgeHeight / 2
        ).fill()
        NSGraphicsContext.restoreGraphicsState()

        let textRect = NSRect(
            x: badgeRect.midX - textSize.width / 2,
            y: badgeRect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        label.draw(in: textRect, withAttributes: attributes)
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
