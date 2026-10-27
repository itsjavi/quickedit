import Foundation
import SwiftTreeSitter

/// A waiting reparse to run off the main thread (`SyntaxHighlighter.beginPendingParse()`): a copy of the edited
/// tree and a snapshot of the text, so it shares nothing mutable with the highlighter. Tree-sitter trees are safe
/// to use on another thread once copied (`ts_tree_copy`: atomically counted subtrees, copied before an edit
/// changes them).
public struct PendingParse: Sendable {
    let id: Int
    let language: SwiftTreeSitter.Language
    let base: Tree
    let units: [unichar]
    /// Lumiose `<style>` contents, blanked for the host grammar.
    let masks: [NSRange]?

    /// Parses the snapshot on the calling thread, with a parser of its own.
    public func run() -> ParsedTree {
        let clock = ContinuousClock()
        let start = clock.now
        let parser = Parser()
        try? parser.setLanguage(language)
        let text = units.withUnsafeBufferPointer { buffer in
            buffer.isEmpty ? "" as NSString : NSString(characters: buffer.baseAddress!, length: buffer.count)
        }
        let readBlock: Parser.ReadBlock
        if let masks {
            readBlock = TextChunks.readBlock(for: text) { buffer, location in StyleScan.blank(masks, in: buffer, at: location) }
        } else {
            readBlock = TextChunks.readBlock(for: text)
        }
        var tree: Tree?
        var changed: [NSRange] = []
        if let parsed = parser.parse(tree: base, readBlock: readBlock) {
            changed = parsed.changedRanges(from: base).map { $0.bytes.range }
            tree = parsed.copy()
        }
        return ParsedTree(id: id, tree: tree, changed: changed, duration: clock.now - start)
    }
}

/// The result of `PendingParse.run()`, for `SyntaxHighlighter.finishPendingParse(_:)`.
public struct ParsedTree: Sendable {
    let id: Int
    /// Nil when the parse failed.
    let tree: Tree?
    /// Tree-sitter's changed ranges, in the snapshot's coordinates.
    let changed: [NSRange]
    /// How long the parse took (off the main thread).
    public let duration: Duration
}
