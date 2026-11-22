import Foundation
import Testing
@testable import Upkeep

// extensionsGallery blocks copied from the shipped Cursor 3.31.15, VSCodium
// 1.143.17232, and Devin (formerly Windsurf) 3.14.30833 product.json files.
private let cursorProduct = #"{"nameShort":"Cursor","extensionsGallery":{"galleryId":"cursor","serviceUrl":"https://marketplace.cursorapi.com/_apis/public/gallery","itemUrl":"https://marketplace.cursorapi.com/items","controlUrl":"https://api2.cursor.sh/extensions-control"}}"#
private let codiumProduct = #"{"nameShort":"VSCodium","extensionsGallery":{"serviceUrl":"https://open-vsx.org/vscode/gallery","itemUrl":"https://open-vsx.org/vscode/item","latestUrlTemplate":"https://open-vsx.org/vscode/gallery/{publisher}/{name}/latest"}}"#
private let devinProduct = #"{"nameShort":"Devin","extensionsGallery":{"serviceUrl":"https://marketplace.windsurf.com/vscode/gallery","itemUrl":"https://marketplace.windsurf.com/vscode/item","controlUrl":"https://marketplace.windsurf.com/vscode/extensions-control"}}"#

@Test func editorGalleriesComeFromProductJSON() throws {
    let cursor = try #require(EditorExtensionGallery.parse(productJSON: Data(cursorProduct.utf8)))
    #expect(cursor.queryURL.absoluteString == "https://marketplace.cursorapi.com/_apis/public/gallery/extensionquery")
    #expect(cursor.itemPage(for: "esbenp.prettier-vscode")?.absoluteString
        == "https://marketplace.cursorapi.com/items?itemName=esbenp.prettier-vscode")

    let codium = try #require(EditorExtensionGallery.parse(productJSON: Data(codiumProduct.utf8)))
    #expect(codium.queryURL.absoluteString == "https://open-vsx.org/vscode/gallery/extensionquery")
    #expect(codium.itemPage(for: "redhat.vscode-yaml")?.absoluteString
        == "https://open-vsx.org/vscode/item?itemName=redhat.vscode-yaml")

    let devin = try #require(EditorExtensionGallery.parse(productJSON: Data(devinProduct.utf8)))
    #expect(devin.queryURL.absoluteString == "https://marketplace.windsurf.com/vscode/gallery/extensionquery")

    // No gallery, or a non-HTTPS one, means the editor's extensions are not checked.
    #expect(EditorExtensionGallery.parse(productJSON: Data(#"{"nameShort":"Code - OSS"}"#.utf8)) == nil)
    #expect(EditorExtensionGallery.parse(productJSON: Data(
        #"{"extensionsGallery":{"serviceUrl":"http://example.com/gallery"}}"#.utf8)) == nil)
}

@Test func editorGalleryIsReadNextToTheCLI() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("Upkeep-Editors-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }

    func editor(_ app: String, cli: String, product: String?) throws -> String {
        let appDirectory = root.appendingPathComponent("\(app)/Contents/Resources/app", isDirectory: true)
        try fileManager.createDirectory(at: appDirectory.appendingPathComponent("bin"), withIntermediateDirectories: true)
        if let product { try product.write(to: appDirectory.appendingPathComponent("product.json"), atomically: true, encoding: .utf8) }
        return appDirectory.appendingPathComponent("bin/\(cli)").path
    }

    let codium = try editor("VSCodium.app", cli: "codium", product: codiumProduct)
    #expect(EditorExtensionGallery.forEditorCLI(codium)?.serviceURL.host == "open-vsx.org")
    // Microsoft's builds fall back to its marketplace; forks without a gallery do not.
    let vscode = try editor("Visual Studio Code.app", cli: "code", product: nil)
    #expect(EditorExtensionGallery.forEditorCLI(vscode) == .visualStudioMarketplace)
    let oss = try editor("Code - OSS.app", cli: "code-oss", product: #"{"nameShort":"Code - OSS"}"#)
    #expect(EditorExtensionGallery.forEditorCLI(oss) == nil)
}

@Test func editorNamesCoverForksAndTheWindsurfRename() {
    let prefix = "/Applications/"
    let suffix = "/Contents/Resources/app/bin/"
    #expect(editorName(for: prefix + "Visual Studio Code.app" + suffix + "code") == "VS Code")
    #expect(editorName(for: prefix + "Visual Studio Code - Insiders.app" + suffix + "code") == "VS Code Insiders")
    #expect(editorName(for: prefix + "Cursor.app" + suffix + "cursor") == "Cursor")
    #expect(editorName(for: prefix + "VSCodium.app" + suffix + "codium") == "VSCodium")
    #expect(editorName(for: prefix + "VSCodium - Insiders.app" + suffix + "codium-insiders") == "VSCodium Insiders")
    #expect(editorName(for: prefix + "Windsurf.app" + suffix + "windsurf") == "Windsurf")
    #expect(editorName(for: prefix + "Devin.app" + suffix + "devin-desktop") == "Devin")
}
