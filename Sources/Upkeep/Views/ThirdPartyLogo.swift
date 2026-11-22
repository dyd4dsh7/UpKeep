import AppKit
import SwiftUI

/// Loads third-party product logos bundled from `Resources/ThirdPartyLogos`.
/// They identify the tool that manages an item. They are trademarks of their
/// owners, are not covered by Upkeep's MIT licence, and are listed with their
/// sources and terms in THIRD_PARTY_NOTICES.md. A name without a bundled logo
/// (for example a brand whose policy requires permission) falls back to a
/// system symbol at the call site. A `<name>-dark` file, when present, is the
/// official or permitted variant for dark appearance.
@MainActor
enum ThirdPartyLogo {
    private static var cache: [String: NSImage] = [:]
    private static var missing = Set<String>()

    static func image(named name: String, in scheme: ColorScheme) -> NSImage? {
        if scheme == .dark, let dark = image(resource: "\(name)-dark") { return dark }
        return image(resource: name)
    }

    private static func image(resource: String) -> NSImage? {
        if let image = cache[resource] { return image }
        guard !missing.contains(resource), let url = url(named: resource),
              let image = NSImage(contentsOf: url) else {
            missing.insert(resource)
            return nil
        }
        cache[resource] = image
        return image
    }

    nonisolated static func url(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "png")
            ?? Bundle.module.url(forResource: name, withExtension: "svg")
    }

    /// Logos Upkeep is permitted to show; everything else uses a system symbol.
    nonisolated static let bundledNames: Set<String> = [
        "bun", "cargo", "composer", "deno", "github", "homebrew", "lmstudio",
        "mise", "nix", "pipx", "pnpm", "rubygems", "rustup", "yarn"
    ]
}
