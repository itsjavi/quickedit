import Foundation

/// The Material Icon Theme's file and folder icons: VS Code's icon theme format, vendored in `Resources/MaterialIcons`
/// by `scripts/vendor-material-icons.sh` (`material-icons.json`, the release's theme cut down to the icons QuickEdit
/// keeps, plus QuickEdit's additions in `quickedit-icons.json`, which win). Names resolve as in VS Code: the file name, then its extensions from the
/// longest (`d.ts` before `ts`), then its language, then the default icon. With `light`, the theme's light variants
/// win at each step.
public struct MaterialIconTheme: Sendable {
    struct Associations: Sendable {
        var fileNames: [String: String] = [:]
        var fileExtensions: [String: String] = [:]
        var languageIds: [String: String] = [:]
        var folderNames: [String: String] = [:]
        var folderNamesExpanded: [String: String] = [:]

        init() {}

        init(_ json: [String: Any]) {
            fileNames = json["fileNames"] as? [String: String] ?? [:]
            fileExtensions = json["fileExtensions"] as? [String: String] ?? [:]
            languageIds = json["languageIds"] as? [String: String] ?? [:]
            folderNames = json["folderNames"] as? [String: String] ?? [:]
            folderNamesExpanded = json["folderNamesExpanded"] as? [String: String] ?? [:]
        }

        mutating func merge(_ other: Associations) {
            fileNames.merge(other.fileNames) { $1 }
            fileExtensions.merge(other.fileExtensions) { $1 }
            languageIds.merge(other.languageIds) { $1 }
            folderNames.merge(other.folderNames) { $1 }
            folderNamesExpanded.merge(other.folderNamesExpanded) { $1 }
        }
    }

    private var dark = Associations()
    private var light = Associations()
    /// Icon id → SVG file name in the theme's `icons` folder.
    private var files: [String: String] = [:]
    private var defaultFile = "file"
    private var defaultFolder = "folder"
    private var defaultFolderExpanded = "folder-open"

    /// Reads `material-icons.json` and, next to it, `quickedit-icons.json` when present.
    public init(directory: URL) throws {
        try add(Data(contentsOf: directory.appendingPathComponent("material-icons.json")))
        if let additions = try? Data(contentsOf: directory.appendingPathComponent("quickedit-icons.json")) {
            try add(additions)
        }
    }

    /// A theme from icon theme JSON documents, later ones winning.
    public init(themes: [Data]) throws {
        for theme in themes { try add(theme) }
    }

    private mutating func add(_ data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for (id, definition) in json["iconDefinitions"] as? [String: [String: Any]] ?? [:] {
            if let path = definition["iconPath"] as? String { files[id] = (path as NSString).lastPathComponent }
        }
        dark.merge(Associations(json))
        light.merge(Associations(json["light"] as? [String: Any] ?? [:]))
        if let file = json["file"] as? String { defaultFile = file }
        if let folder = json["folder"] as? String { defaultFolder = folder }
        if let folder = json["folderExpanded"] as? String { defaultFolderExpanded = folder }
    }

    /// The icon for a file named `name` (the last path component; any case). `languageID` is VS Code's id of the
    /// file's language, when known (`typescriptreact`, `shellscript`, …), evaluated only when the name doesn't decide.
    public func fileIcon(named name: String, languageID: @autoclosure () -> String? = nil, light isLight: Bool) -> String {
        let name = name.lowercased()
        let maps = isLight ? [light, dark] : [dark]
        for map in maps { if let icon = map.fileNames[name] { return icon } }
        // "a.spec.ts": "spec.ts", then "ts". A dotfile's name counts as an extension (".gitignore": "gitignore").
        let segments = name.split(separator: ".", omittingEmptySubsequences: false)
        if segments.count > 1 {
            for start in 1..<segments.count {
                let suffix = segments[start...].joined(separator: ".")
                for map in maps { if let icon = map.fileExtensions[suffix] { return icon } }
            }
        }
        if let languageID = languageID() {
            for map in maps { if let icon = map.languageIds[languageID] { return icon } }
        }
        return defaultFile
    }

    /// The icon for a folder named `name` (any case), open or closed.
    public func folderIcon(named name: String, expanded: Bool, light isLight: Bool) -> String {
        let name = name.lowercased()
        for map in isLight ? [light, dark] : [dark] {
            if let icon = (expanded ? map.folderNamesExpanded : map.folderNames)[name] { return icon }
        }
        return expanded ? defaultFolderExpanded : defaultFolder
    }

    /// The SVG file of an icon, in the theme's `icons` folder.
    public func fileName(ofIcon id: String) -> String? {
        files[id]
    }

    /// Every icon id the theme defines (tests).
    public var iconIDs: [String] { Array(files.keys) }
}
