import AppKit
import SwiftUI
import Testing
@testable import Upkeep

@MainActor
@Test func dockIconFollowsAppearanceWithoutCustomTileDrawing() async throws {
    let app = NSApplication.shared
    let originalAppearance = app.appearance
    defer {
        app.appearance = originalAppearance
        AppBrand.applyDockPresentation(updateCount: 0)
    }
    app.appearance = NSAppearance(named: .aqua)
    AppBrand.applyDockPresentation(updateCount: 5)
    #expect(AppBrand.appliedDarkAppearance == false)
    #expect(app.dockTile.contentView is NSImageView)
    #expect(app.dockTile.badgeLabel == "5")

    let lightPixels = app.applicationIconImage.tiffRepresentation
    app.appearance = NSAppearance(named: .darkAqua)
    for _ in 0..<100 {
        if AppBrand.appliedDarkAppearance == true { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(AppBrand.appliedDarkAppearance == true)
    #expect(app.applicationIconImage.tiffRepresentation != lightPixels)
    #expect(app.dockTile.contentView is NSImageView)
    #expect(app.dockTile.badgeLabel == "5")

    app.appearance = NSAppearance(named: .aqua)
    for _ in 0..<100 {
        if AppBrand.appliedDarkAppearance == false { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(AppBrand.appliedDarkAppearance == false)
    AppBrand.applyDockPresentation(updateCount: 0)
    #expect(app.dockTile.badgeLabel == nil)
}

@MainActor
@Test func dockArtworkHasMatchingTransparentMarginsInBothThemes() throws {
    for scheme: SwiftUI.ColorScheme in [.light, .dark] {
        let image = AppBrand.dockImage(for: scheme)
        let data = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: data))
        let y = rep.pixelsHigh / 2
        let occupied = (0..<rep.pixelsWide).filter { (rep.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.5 }
        let first = try #require(occupied.first)
        let last = try #require(occupied.last)
        let width = Double(last - first + 1) / Double(rep.pixelsWide)
        #expect(width > 0.79 && width < 0.82)
        #expect(Double(first) / Double(rep.pixelsWide) > 0.09)
        #expect(Double(rep.pixelsWide - 1 - last) / Double(rep.pixelsWide) > 0.09)
    }
}
