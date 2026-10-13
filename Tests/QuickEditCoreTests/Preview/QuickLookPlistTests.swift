import Foundation
import Testing
import UniformTypeIdentifiers

/// The Quick Look preview and thumbnail extensions claim the same types (decision-5), each either a system type or
/// one the app's Info.plist declares.
@Suite struct QuickLookPlistTests {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources")

    private static func plist(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: resources.appendingPathComponent(path))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private static func extensionTypes(_ path: String) throws -> [String] {
        let attributes = try #require((try plist(path)["NSExtension"] as? [String: Any])?["NSExtensionAttributes"] as? [String: Any])
        return try #require(attributes["QLSupportedContentTypes"] as? [String])
    }

    @Test func previewAndThumbnailClaimTheSameTypes() throws {
        let preview = try Self.extensionTypes("QuickLook/Info.plist")
        #expect(preview == (try Self.extensionTypes("QuickLook/Thumbnail-Info.plist")))
        for type in ["public.mpeg-2-transport-stream", "public.yaml", "public.toml", "public.css",
                     "com.itsjavi.lumiose.stsx", "com.itsjavi.lumiose.sjsx"] {
            #expect(preview.contains(type), "\(type) not claimed")
        }
    }

    @Test func claimedTypesAreSystemOrDeclaredByTheApp() throws {
        let app = try Self.plist("Info.plist")
        let declarations = (app["UTImportedTypeDeclarations"] as? [[String: Any]] ?? [])
            + (app["UTExportedTypeDeclarations"] as? [[String: Any]] ?? [])
        let declared = Set(declarations.compactMap { $0["UTTypeIdentifier"] as? String })
        for type in try Self.extensionTypes("QuickLook/Info.plist") where !declared.contains(type) {
            let system = UTType(type)
            #expect(system != nil && system?.isDeclared == true, "\(type) is neither a system type nor declared in Info.plist")
        }
    }

    @Test func extensionPointsAndPrincipalClasses() throws {
        let preview = try #require(try Self.plist("QuickLook/Info.plist")["NSExtension"] as? [String: Any])
        #expect(preview["NSExtensionPointIdentifier"] as? String == "com.apple.quicklook.preview")
        #expect(preview["NSExtensionPrincipalClass"] as? String == "QuickEditQuickLook.PreviewViewController")
        // View-based: Finder's preview pane ignores data-based previews.
        let attributes = try #require(preview["NSExtensionAttributes"] as? [String: Any])
        #expect(attributes["QLIsDataBasedPreview"] as? Bool == false)
        let thumbnail = try #require(try Self.plist("QuickLook/Thumbnail-Info.plist")["NSExtension"] as? [String: Any])
        #expect(thumbnail["NSExtensionPointIdentifier"] as? String == "com.apple.quicklook.thumbnail")
        #expect(thumbnail["NSExtensionPrincipalClass"] as? String == "QuickEditThumbnail.ThumbnailProvider")
    }
}
