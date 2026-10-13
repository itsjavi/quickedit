import Foundation
import QuickEditSyntax
import Testing
import UniformTypeIdentifiers

/// Every extension the language registry highlights is declared in Info.plist (decision-5): either through an
/// imported type, or because the system's type for it is one QuickEdit claims (or conforms to one, ignoring the
/// catch-all `public.data`/`public.text`).
@Suite struct InfoPlistTypesTests {
    nonisolated(unsafe) private static let plist: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let data = try! Data(contentsOf: url)
        return try! PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    }()

    private static var claimedTypes: Set<String> {
        let types = plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        return Set(types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
    }

    private static var importedExtensions: Set<String> {
        let declarations = plist["UTImportedTypeDeclarations"] as? [[String: Any]] ?? []
        return Set(declarations.flatMap { declaration in
            ((declaration["UTTypeTagSpecification"] as? [String: Any])?["public.filename-extension"] as? [String]) ?? []
        })
    }

    @Test func everyRegistryExtensionIsDeclared() {
        let claimed = Self.claimedTypes
        let specific = claimed.subtracting(["public.data", "public.text", "public.item", "public.content"]).compactMap(UTType.init)
        let imported = Self.importedExtensions
        var missing: [String] = []
        for language in LanguageRegistry.all {
            for ext in language.extensions where !imported.contains(ext) {
                guard let type = UTType(filenameExtension: ext), !type.isDynamic,
                      claimed.contains(type.identifier) || specific.contains(where: { type.conforms(to: $0) })
                else {
                    missing.append("\(language.id): .\(ext)")
                    continue
                }
            }
        }
        #expect(missing.isEmpty, "Not declared in Info.plist: \(missing.joined(separator: ", "))")
    }

    @Test func importedTypesConformToText() {
        let declarations = Self.plist["UTImportedTypeDeclarations"] as? [[String: Any]] ?? []
        for declaration in declarations {
            let conforms = declaration["UTTypeConformsTo"] as? [String] ?? []
            let parents = conforms.compactMap(UTType.init)
            #expect(parents.contains { $0.conforms(to: .text) }, "\(declaration["UTTypeIdentifier"] ?? "?") must conform to text for Quick Look")
        }
    }

    @Test func typeScriptIsClaimedDespiteTheVideoType() {
        #expect(Self.claimedTypes.contains("public.mpeg-2-transport-stream"))
        #expect(Self.claimedTypes.contains("public.plain-text"))
    }
}
