import Foundation

@testable import QuickEditSyntax

/// A fixture highlighted from scratch, with helpers to ask what kind a piece of text got.
struct Highlighted {
    let text: NSString
    let tokens: [SyntaxToken]

    init(_ source: String, language id: String) {
        guard let language = LanguageRegistry.language(id: id) else { fatalError("unknown language \(id)") }
        let highlighter = SyntaxHighlighter(language: language)
        text = source as NSString
        highlighter.setText(text)
        tokens = highlighter.tokens(in: NSRange(location: 0, length: text.length))
    }

    /// The kind of the token covering all of `needle` (searched after `anchor` when given), or nil when no
    /// single token covers it.
    func kind(of needle: String, after anchor: String? = nil) -> TokenKind? {
        guard let range = find(needle, after: anchor) else { return nil }
        return tokens.first { $0.range.location <= range.location && $0.range.upperBound >= range.upperBound }?.kind
    }

    /// Every kind touching `needle`.
    func kinds(within needle: String, after anchor: String? = nil) -> Set<TokenKind> {
        guard let range = find(needle, after: anchor) else { return [] }
        return Set(tokens.filter { $0.range.clipped(to: range) != nil }.map(\.kind))
    }

    func find(_ needle: String, after anchor: String?) -> NSRange? {
        var start = 0
        if let anchor {
            let anchorRange = text.range(of: anchor)
            guard anchorRange.location != NSNotFound else { return nil }
            start = anchorRange.upperBound
        }
        let range = text.range(of: needle, options: [], range: NSRange(location: start, length: text.length - start))
        return range.location == NSNotFound ? nil : range
    }

    /// "text → kind" lines, for failure messages.
    var dump: String {
        tokens.map { "\(text.substring(with: $0.range).debugDescription) → \($0.kind)" }.joined(separator: "\n")
    }
}

/// A deterministic random number generator for reproducible edit sequences.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
