/// A comment pair such as `/* … */`.
public struct BlockComment: Sendable, Hashable {
    public let open: String
    public let close: String

    public init(open: String, close: String) {
        self.open = open
        self.close = close
    }
}

/// A language the editor knows: how files are detected, how they're commented and how they're highlighted.
/// Several languages can share a grammar (JSON, JSONC and JSON Lines; shell and dotenv).
public struct Language: Sendable, Hashable, Identifiable {
    /// Stable identifier ("typescript", "tsx", "plaintext", "csv", …).
    public let id: String
    public let displayName: String
    /// Lowercase extensions without the dot.
    public let extensions: [String]
    /// Exact file names ("Dockerfile", "go.mod"), matched case-insensitively.
    public let fileNames: [String]
    /// Globs with `*` and `?` (".env.*", "tsconfig*.json"), matched case-insensitively.
    public let fileNamePatterns: [String]
    /// Interpreter names from a `#!` line ("bash", "python3", "node"); trailing version numbers are ignored.
    public let shebangInterpreters: [String]
    public let lineComment: String?
    public let blockComment: BlockComment?
    /// Indent with tabs by default (Makefile, Go).
    public let prefersTabs: Bool

    let highlighting: Highlighting
    /// Extra names for Markdown fenced code info strings and injections ("ts", "yml", "sh").
    let aliases: [String]

    /// Whether the highlighter produces tokens for this language.
    public var hasHighlighting: Bool {
        if case .none = highlighting { return false }
        return true
    }

    public static func == (lhs: Language, rhs: Language) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// How a language is highlighted.
enum Highlighting: Sendable, Hashable {
    case none
    /// A vendored tree-sitter grammar by name ("typescript", "bash").
    case grammar(String)
    /// Rainbow columns split by a delimiter (UTF-16 code unit), with double-quoted fields.
    case delimited(UInt16)
}
