import AppKit
import Combine
import SwiftUI

@MainActor
enum AppBrand {
    @MainActor private static var appliedUpdateCount: Int?
    private(set) static var appliedDarkAppearance: Bool?
    private static var appearanceObserver: AnyCancellable?
    private static let lightImage = loadImage(named: "AppIcon")
    private static let darkImage = loadImage(named: "AppIconDark")
    private static let lightDockImage = makeDockImage(from: lightImage)
    private static let darkDockImage = makeDockImage(from: darkImage)

    static func dockImage(for colorScheme: ColorScheme) -> NSImage {
        colorScheme == .dark ? darkDockImage : lightDockImage
    }

    private static func makeDockImage(from artwork: NSImage) -> NSImage {
        // The source plate occupies about 976 of 1024 pixels. Drawing its
        // canvas at 864 pixels gives the plate an approximately 824px footprint.
        // Runtime applicationIconImage replacements need this transparent margin.
        NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
            artwork.draw(in: NSRect(x: 80, y: 80, width: 864, height: 864),
                         from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }

    private static func loadImage(named name: String) -> NSImage {
        // Native SwiftPM's generated Bundle.module accessor checks beside the
        // executable and in its build directory, not Contents/Resources. Resolve
        // the packaged bundle first so distribution works after build cleanup.
        let packagedResources = Bundle.main.url(forResource: "Upkeep_Upkeep", withExtension: "bundle")
            .flatMap(Bundle.init(url:))
        let resources = packagedResources ?? Bundle.module
        if let url = resources.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Upkeep") ?? NSImage()
    }

    static func image(for colorScheme: ColorScheme) -> NSImage {
        colorScheme == .dark ? darkImage : lightImage
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
        if appearanceObserver == nil {
            appearanceObserver = application.publisher(for: \.effectiveAppearance).sink { _ in
                Task { @MainActor in
                    refreshDockPresentationIfNeeded(updateCount: appliedUpdateCount ?? 0)
                }
            }
        }
        let isDark = application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        guard force || appliedUpdateCount != updateCount || appliedDarkAppearance != isDark else { return }

        // AppKit sizes the image and draws the badge. Only choose the artwork;
        // never replace the Dock tile with a custom drawing view.
        application.dockTile.contentView = nil
        application.applicationIconImage = dockImage(for: isDark ? .dark : .light)
        application.dockTile.badgeLabel = updateCount > 0
            ? (updateCount > 999 ? "999+" : String(updateCount))
            : nil
        application.dockTile.display()
        appliedUpdateCount = updateCount
        appliedDarkAppearance = isDark
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
