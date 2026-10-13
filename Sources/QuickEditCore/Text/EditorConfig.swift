import Foundation

/// The `.editorconfig` properties QuickEdit understands, resolved for one file. Nil means "not set".
public struct EditorConfigProperties: Equatable, Sendable {
    public var indentStyle: IndentStyle?
    /// Columns per indentation level. `indent_size = tab` resolves to `tabWidth` (nil when that is unknown too).
    public var indentSize: Int?
    public var tabWidth: Int?
    public var endOfLine: LineEnding?
    public var charset: TextEncoding?
    public var trimTrailingWhitespace: Bool?
    public var insertFinalNewline: Bool?

    public init(
        indentStyle: IndentStyle? = nil, indentSize: Int? = nil, tabWidth: Int? = nil, endOfLine: LineEnding? = nil,
        charset: TextEncoding? = nil, trimTrailingWhitespace: Bool? = nil, insertFinalNewline: Bool? = nil
    ) {
        self.indentStyle = indentStyle
        self.indentSize = indentSize
        self.tabWidth = tabWidth
        self.endOfLine = endOfLine
        self.charset = charset
        self.trimTrailingWhitespace = trimTrailingWhitespace
        self.insertFinalNewline = insertFinalNewline
    }

    public var isEmpty: Bool { self == EditorConfigProperties() }
}

/// EditorConfig (https://spec.editorconfig.org) file parsing, glob matching and per-file resolution.
public enum EditorConfig {
    /// Walks from the file's folder up to a file with `root = true` (or the filesystem root). Sections apply from the
    /// outermost file inward and top to bottom, so the nearest file and the last matching section win. `unset`
    /// clears a property set further out.
    public static func properties(
        for fileURL: URL,
        readFile: (URL) -> String? = { try? String(contentsOf: $0, encoding: .utf8) }
    ) -> EditorConfigProperties {
        let filePath = fileURL.standardizedFileURL.path
        var configs: [(directory: String, sections: [(glob: String, properties: [String: String])])] = []
        var directory = (filePath as NSString).deletingLastPathComponent
        while true {
            let configURL = URL(fileURLWithPath: directory).appendingPathComponent(".editorconfig")
            if let text = readFile(configURL) {
                let parsed = parse(text)
                configs.append((directory, parsed.sections))
                if parsed.isRoot { break }
            }
            if directory == "/" || directory.isEmpty { break }
            directory = (directory as NSString).deletingLastPathComponent
        }

        var raw: [String: String] = [:]
        for config in configs.reversed() {
            let prefix = config.directory.hasSuffix("/") ? config.directory : config.directory + "/"
            guard filePath.hasPrefix(prefix) else { continue }
            let relativePath = String(filePath.dropFirst(prefix.count))
            for section in config.sections where matches(glob: section.glob, relativePath: relativePath) {
                raw.merge(section.properties) { _, new in new }
            }
        }
        return resolve(raw)
    }

    /// Parses an `.editorconfig` file: `root = true` before the first section, then `[glob]` sections of
    /// `key = value` pairs. Keys are lowercased; values keep their case (known values are compared
    /// case-insensitively later). `#` and `;` start comment lines. Malformed lines are skipped.
    public static func parse(_ text: String) -> (isRoot: Bool, sections: [(glob: String, properties: [String: String])]) {
        var isRoot = false
        var sections: [(glob: String, properties: [String: String])] = []
        var body = Substring(text)
        if body.first == "\u{FEFF}" { body = body.dropFirst() }
        for rawLine in body.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let first = line.first, first != "#", first != ";" else { continue }
            if first == "[" {
                guard line.count >= 2, line.last == "]" else { continue }
                sections.append((String(line.dropFirst().dropLast()), [:]))
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            if sections.isEmpty {
                if key == "root" { isRoot = value.lowercased() == "true" }
            } else {
                sections[sections.count - 1].properties[key] = value
            }
        }
        return (isRoot, sections)
    }

    /// Matches an EditorConfig section glob against a path relative to the `.editorconfig` folder: `*` (not `/`),
    /// `**` (anything), `?`, `[abc]`, `[!abc]`, `[a-z]`, `{a,b}` (nestable), `{1..3}` and `\` escapes. A glob without
    /// `/` matches the file name at any depth; one with `/` is anchored to the `.editorconfig` folder.
    public static func matches(glob: String, relativePath: String) -> Bool {
        let path = relativePath.hasPrefix("/") ? relativePath : "/" + relativePath
        guard let compiled = EditorConfigGlob.compile(glob) else { return false }
        return compiled.matches(path)
    }

    // MARK: - Resolution

    static func resolve(_ raw: [String: String]) -> EditorConfigProperties {
        func value(_ key: String) -> String? {
            // Known values are single tokens; dropping anything after whitespace tolerates inline comments.
            guard let value = raw[key]?.lowercased().split(whereSeparator: \.isWhitespace).first else { return nil }
            return value == "unset" ? nil : String(value)
        }
        func positiveInt(_ text: String?) -> Int? { text.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil } }
        func bool(_ text: String?) -> Bool? {
            switch text {
            case "true": true
            case "false": false
            default: nil
            }
        }

        var properties = EditorConfigProperties()
        properties.indentStyle = switch value("indent_style") {
        case "tab": .tabs
        case "space": .spaces
        default: nil
        }
        properties.tabWidth = positiveInt(value("tab_width"))
        var indentSize = value("indent_size")
        // Spec defaults: tab indentation implies indent_size = tab; a numeric indent_size implies tab_width.
        if indentSize == nil, properties.indentStyle == .tabs { indentSize = "tab" }
        if indentSize == "tab" {
            properties.indentSize = properties.tabWidth
        } else if let size = positiveInt(indentSize) {
            properties.indentSize = size
            if properties.tabWidth == nil { properties.tabWidth = size }
        }
        properties.endOfLine = switch value("end_of_line") {
        case "lf": .lf
        case "crlf": .crlf
        case "cr": .cr
        default: nil
        }
        properties.charset = switch value("charset") {
        case "utf-8": .utf8
        case "utf-8-bom": .utf8WithBOM
        case "utf-16le": .utf16LittleEndian
        case "utf-16be": .utf16BigEndian
        case "latin1": .isoLatin1
        default: nil
        }
        properties.trimTrailingWhitespace = bool(value("trim_trailing_whitespace"))
        properties.insertFinalNewline = bool(value("insert_final_newline"))
        return properties
    }
}
