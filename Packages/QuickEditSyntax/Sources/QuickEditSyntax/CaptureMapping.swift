/// What a highlight query capture does to the text it covers.
enum CaptureStyle: Hashable, Sendable {
    case token(TokenKind)
    /// `@none`: removes any outer capture's kind (e.g. fenced code content inside a raw block).
    case clear
}

/// Maps tree-sitter capture names to token kinds. Grammars use the tree-sitter, Neovim (`@keyword.conditional`,
/// `@variable.member`) and older Neovim (`@text.title`, `@conditional`) conventions, so a name is looked up
/// whole and then with its last component dropped (`keyword.control.return` → `keyword.control` → `keyword`).
/// Names that map to nothing produce no token.
enum CaptureMapping {
    static func style(forCapture name: String) -> CaptureStyle? {
        if name.hasPrefix("_") || name.hasPrefix("injection.") || name.hasPrefix("local.") {
            return nil
        }
        var candidate = Substring(name)
        while true {
            if let style = table[String(candidate)] {
                return style
            }
            guard let dot = candidate.lastIndex(of: ".") else { return nil }
            candidate = candidate[..<dot]
        }
    }

    private static let table: [String: CaptureStyle] = {
        var table: [String: CaptureStyle] = [:]
        func map(_ kind: TokenKind, _ names: String...) {
            for name in names { table[name] = .token(kind) }
        }
        map(
            .keyword, "keyword", "conditional", "repeat", "include", "exception", "storageclass", "define",
            "preproc", "debug", "type.qualifier", "keyword.storage")
        map(.string, "string", "character", "string.special.path", "text.literal.string")
        map(
            .stringSpecial, "string.escape", "string.special", "string.regex", "string.regexp", "escape",
            "character.special", "punctuation.special", "constant.character.escape", "string.interpolation")
        map(.comment, "comment")
        map(.number, "number", "float", "constant.numeric")
        map(.constant, "constant", "boolean", "constant.builtin", "constant.macro", "string.special.symbol", "symbol")
        map(.function, "function", "method", "macro", "function.macro", "constructor.builtin")
        map(.type, "type", "constructor", "class", "interface", "enum", "struct")
        map(
            .property, "property", "field", "variable.member", "variable.other.member", "string.special.key",
            "property.definition")
        map(.variable, "variable", "identifier")
        map(.variableBuiltin, "variable.builtin", "variable.language")
        map(.parameter, "variable.parameter", "parameter")
        map(.namespace, "module", "namespace")
        map(.label, "label")
        map(.operator, "operator", "keyword.operator.symbol")
        map(.punctuation, "punctuation", "tag.delimiter", "delimiter")
        map(.tag, "tag", "tag.builtin")
        map(.attribute, "attribute", "tag.attribute", "attribute.builtin")
        map(.heading, "text.title", "markup.heading", "title")
        map(.emphasis, "text.emphasis", "markup.italic", "emphasis")
        map(.strong, "text.strong", "markup.bold", "markup.strong", "strong")
        map(
            .link, "text.uri", "text.reference", "markup.link", "string.special.url", "string.special.uri", "link")
        map(.codeSpan, "text.literal", "markup.raw")
        map(.quote, "text.quote", "markup.quote")
        map(.listMarker, "markup.list", "punctuation.list_marker")
        map(.inserted, "diff.plus", "diff.addition", "markup.inserted", "text.diff.add")
        map(.deleted, "diff.minus", "diff.deletion", "markup.deleted", "text.diff.delete")
        map(.diffMeta, "diff.delta", "diff.meta", "markup.changed")
        map(.invalid, "invalid", "tag.error")
        table["none"] = .clear
        return table
    }()
}
