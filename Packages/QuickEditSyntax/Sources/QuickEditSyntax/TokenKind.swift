import Foundation

/// What a highlighted range is, independent of the grammar that produced it. The app maps kinds to colors.
public enum TokenKind: Hashable, Sendable {
    case keyword
    case string
    /// Escapes, regular expressions, interpolation punctuation and other special parts of strings.
    case stringSpecial
    case comment
    case number
    /// `true`, `null`, builtin and all-caps constants.
    case constant
    case function
    case type
    case property
    case variable
    /// `this`, `self`, `super` and similar.
    case variableBuiltin
    case parameter
    case namespace
    case label
    case `operator`
    case punctuation
    case tag
    case attribute
    case heading
    case emphasis
    case strong
    case link
    case codeSpan
    case quote
    case listMarker
    case inserted
    case deleted
    case diffMeta
    case invalid
    /// A CSV/TSV column (0-based). The app cycles colors by index.
    case column(Int)
}

/// A highlighted range in UTF-16 (`NSString`) offsets.
public struct SyntaxToken: Sendable, Equatable {
    public let range: NSRange
    public let kind: TokenKind

    public init(range: NSRange, kind: TokenKind) {
        self.range = range
        self.kind = kind
    }
}

extension TokenKind {
    /// Every case except `column`, in a stable order; `paletteIndex` indexes into it.
    static let fixed: [TokenKind] = [
        .keyword, .string, .stringSpecial, .comment, .number, .constant, .function, .type, .property, .variable,
        .variableBuiltin, .parameter, .namespace, .label, .operator, .punctuation, .tag, .attribute, .heading,
        .emphasis, .strong, .link, .codeSpan, .quote, .listMarker, .inserted, .deleted, .diffMeta, .invalid,
    ]

    static let paletteIndices: [TokenKind: Int16] = Dictionary(
        uniqueKeysWithValues: fixed.enumerated().map { ($0.element, Int16($0.offset)) }
    )
}
