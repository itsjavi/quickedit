import Foundation
import SwiftTreeSitter

/// A foldable region of the text.
public struct FoldRegion: Sendable, Hashable {
    /// The UTF-16 range that disappears when the region is folded. For bracketed and tagged regions it runs from
    /// the end of the opening line (just after `{`, `[`, `(`, a start tag, or whatever follows them on that line)
    /// to just before the closing token, so a folded region reads `{⋯}`. For indentation-based regions (YAML
    /// mappings, TOML tables, Python blocks, Markdown sections) it runs from the end of the first line to the end
    /// of the last line with content. It always contains a line break.
    public let hidden: NSRange
    /// The 0-based line where `hidden` starts (the line that keeps the fold marker).
    public let startLine: Int
    /// The 0-based line where `hidden` ends (the closing token's line, or the last content line).
    public let endLine: Int

    public init(hidden: NSRange, startLine: Int, endLine: Int) {
        self.hidden = hidden
        self.startLine = startLine
        self.endLine = endLine
    }
}

/// Turns the nodes `FoldRules` names into fold regions.
///
/// A node whose first and last children are an opener and a closer (`{`…`}`, `[`…`]`, `(`…`)`, start/end tags,
/// code fences) folds between them; when its last child starts on its first line (a function and its body
/// block), that child is examined instead. Anything else folds by lines.
struct FoldBuilder {
    let text: NSString
    let lines: LineIndex

    /// Closing tokens: brackets, Ruby/Lua `end`, Objective-C `@end`, Nix `''`.
    private static let closingTokens: Set<String> = ["}", "]", ")", "end", "@end", "''"]
    private static let closingNodes: Set<String> = [
        "end_tag", "ETag", "jsx_closing_element", "fenced_code_block_delimiter",
        // HCL braces, Svelte {/if}-style block ends, CMake end commands
        "block_end", "object_end", "tuple_end", "if_end", "each_end", "await_end", "key_end", "snippet_end",
        "endfunction_command", "endmacro_command", "endforeach_command", "endwhile_command", "endblock_command",
        "endif_command",
    ]

    /// Walks the multi-line part of the tree (a single-line node can't contain a fold) and folds the nodes the
    /// grammar's rules name.
    /// Appends the regions of `tree`'s foldable nodes; with `bytes`, only nodes overlapping it are visited.
    func collect(
        tree: MutableTree, rules: [Int: [FoldRules.Rule]], into regions: inout [FoldRegion], within bytes: Range<UInt32>? = nil
    ) {
        guard !rules.isEmpty, let root = tree.rootNode else { return }
        let cursor = root.treeCursor
        while true {
            if let node = cursor.currentNode {
                let points = node.pointRange
                let overlaps = bytes.map { node.byteRange.upperBound > $0.lowerBound && node.byteRange.lowerBound < $0.upperBound } ?? true
                if overlaps, points.upperBound.row > points.lowerBound.row {
                    if node.isNamed, let candidates = rules[node.symbol], candidates.contains(where: { $0.matches(node) }),
                        let region = region(for: node)
                    {
                        regions.append(region)
                    }
                    if cursor.goToFirstChild() { continue }
                }
            }
            while true {
                if cursor.gotoNextSibling() {
                    // Siblings that start past the range end this level.
                    guard let bytes, let next = cursor.currentNode, next.byteRange.lowerBound >= bytes.upperBound else { break }
                }
                guard cursor.gotoParent() else { return }
            }
        }
    }

    func region(for node: Node) -> FoldRegion? {
        let startRow = node.pointRange.lowerBound.row
        var container = node
        while container.childCount >= 2,
            let first = container.child(at: 0),
            let last = container.child(at: container.childCount - 1)
        {
            if isCloser(last) {
                return bracketed(opener: first, closer: last)
            }
            guard last.pointRange.lowerBound.row == startRow else { break }
            container = last
        }
        return byLines(node)
    }

    private func isCloser(_ node: Node) -> Bool {
        guard let type = node.nodeType else { return false }
        return node.isNamed ? Self.closingNodes.contains(type) : Self.closingTokens.contains(type)
    }

    private func bracketed(opener: Node, closer: Node) -> FoldRegion? {
        let openerEnd = Int(opener.byteRange.upperBound / 2)
        let start = max(openerEnd, contentEnd(ofLineAt: openerEnd))
        return make(start: start, end: Int(closer.byteRange.lowerBound / 2))
    }

    private func byLines(_ node: Node) -> FoldRegion? {
        let range = node.range
        let start = contentEnd(ofLineAt: range.location)
        var end = min(range.upperBound, text.length)
        while end > start, Self.isWhitespace(text.character(at: end - 1)) { end -= 1 }
        return make(start: start, end: end)
    }

    private func make(start: Int, end: Int) -> FoldRegion? {
        guard end > start else { return nil }
        let startLine = lines.row(at: start)
        let endLine = lines.row(at: end)
        guard endLine > startLine else { return nil }
        return FoldRegion(hidden: NSRange(location: start, length: end - start), startLine: startLine, endLine: endLine)
    }

    /// The end of the line containing `offset`, before trailing whitespace and the line break.
    private func contentEnd(ofLineAt offset: Int) -> Int {
        let row = lines.row(at: offset)
        let lineStart = lines.starts[row]
        var end = row + 1 < lines.starts.count ? lines.starts[row + 1] : text.length
        while end > lineStart, Self.isWhitespace(text.character(at: end - 1)) { end -= 1 }
        return end
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }

    /// Unique regions sorted by location, outer regions before the ones they contain.
    static func normalized(_ regions: [FoldRegion]) -> [FoldRegion] {
        var seen = Set<NSRange>()
        return regions.filter { seen.insert($0.hidden).inserted }.sorted {
            $0.hidden.location != $1.hidden.location
                ? $0.hidden.location < $1.hidden.location : $0.hidden.length > $1.hidden.length
        }
    }
}
