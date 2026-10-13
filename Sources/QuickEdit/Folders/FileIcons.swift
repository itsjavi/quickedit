import AppKit
import QuickEditCore
import QuickEditSyntax
import UniformTypeIdentifiers

/// Icons of files and folders in the sidebar and Quick Open: the Material Icon Theme bundled in
/// `Resources/MaterialIcons`, in its light or dark variant for the appearance they're drawn in, or Finder's icons
/// (Settings › File icons, and builds without the theme such as `swift run`).
enum FileIcons {
    private static let directory = Bundle.main.resourceURL?.appendingPathComponent("MaterialIcons", isDirectory: true)
    private static let theme: MaterialIconTheme? = directory.flatMap { try? MaterialIconTheme(directory: $0) }
    private static var images: [String: NSImage] = [:]
    private static let finderFolder = NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder")

    /// Material icons are full colour; Finder's folder symbol takes the accent colour.
    static var usesMaterial: Bool { AppSettings.shared.fileIcons == .material && theme != nil }

    static func file(_ url: URL, appearance: NSAppearance) -> NSImage {
        let name = url.lastPathComponent
        if usesMaterial, let theme {
            let id = theme.fileIcon(named: name, languageID: languageID(of: name), light: isLight(appearance))
            if let image = image(id, in: theme) { return image }
        }
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .plainText)
    }

    static func folder(_ url: URL, expanded: Bool, appearance: NSAppearance) -> NSImage? {
        if usesMaterial, let theme {
            let id = theme.folderIcon(named: url.lastPathComponent, expanded: expanded, light: isLight(appearance))
            if let image = image(id, in: theme) { return image }
        }
        return finderFolder
    }

    private static func isLight(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    private static func image(_ id: String, in theme: MaterialIconTheme) -> NSImage? {
        if let cached = images[id] { return cached }
        guard let directory, let file = theme.fileName(ofIcon: id),
              let image = NSImage(contentsOf: directory.appendingPathComponent("icons").appendingPathComponent(file))
        else { return nil }
        image.size = NSSize(width: 16, height: 16)  // the SVGs' own sizes vary (16 to 960)
        images[id] = image
        return image
    }

    /// VS Code's language id for a file QuickEdit recognizes by name only (a shebang file reads as plain text here).
    private static func languageID(of name: String) -> String? {
        let id = LanguageRegistry.detect(fileName: name, firstLine: nil).id
        switch id {
        case "plaintext": return nil
        case "tsx", "stsx": return "typescriptreact"
        case "sjsx": return "javascriptreact"
        case "objc": return "objective-c"
        case "shell": return "shellscript"
        case "godot-resource": return "gdresource"
        default: return id
        }
    }
}
