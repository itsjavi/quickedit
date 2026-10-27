import Foundation
import SwiftTreeSitter

/// Highlighting with a tree-sitter grammar: one incrementally reparsed tree for the document, plus injected
/// layers (Markdown inline syntax and fenced code, HTML `<script>`/`<style>`) parsed lazily for the ranges that are
/// actually queried and cached until an edit touches them.
///
/// Injections follow tree-sitter's highlighter (`tree-sitter-highlight`): `@injection.content` and
/// `@injection.language` captures, `#set! injection.language`, `injection.include-children` (otherwise the content
/// node's children are excluded) and `injection.combined` (grouped per pattern within the queried range).
///
/// Lumiose components (`stylesheets` set): the host grammar parses the text with `<style>` contents blanked
/// (`StyleScan`), each block's CSS is a layer of its own read with `$` references neutralized, and the references
/// are painted as constants on top.
final class TreeSitterEngine: HighlightEngine {
    static let maximumInjectionDepth = 4
    /// Cache variant of the CSS layers of Lumiose `<style>` blocks (read with `$` references neutralized).
    private static let stylesheetVariant = 1

    private let grammar: GrammarConfiguration
    /// Set for Lumiose components: `<style>` blocks are blanked for the host grammar and parsed as CSS.
    private let stylesheetGrammar: GrammarConfiguration?
    private let parser = Parser()
    private var tree: MutableTree?
    private var text: NSString = ""
    private var lines = LineIndex()
    private var styles = StyleScan()
    private let injections = InjectionCache()

    /// When set and the last incremental parse took at least this long, edits only adjust the tree and the reparse
    /// waits for `parsePending()`: typing in a large Markdown file stays fast, and colours catch up when typing
    /// pauses. Nil parses after every edit.
    var deferredParseThreshold: Duration?
    private var lastParseDuration: Duration = .zero
    private(set) var hasPendingParse = false
    /// The background reparse in flight (`beginPendingParse`), and the root-tree edits made since its snapshot,
    /// replayed onto its tree when it's installed.
    private var inFlight: Int?
    private var lastParseID = 0
    private var editLog: [(edit: InputEdit, oldRange: NSRange, length: Int)] = []

    init(grammar: GrammarConfiguration, stylesheets: GrammarConfiguration? = nil) {
        self.grammar = grammar
        self.stylesheetGrammar = stylesheets
        // Only fails for an ABI the runtime doesn't support, which the vendoring script and tests rule out.
        try? parser.setLanguage(grammar.language)
    }

    func setText(_ text: NSString) {
        self.text = text
        lines = LineIndex(text: text)
        injections.removeAll()
        if stylesheetGrammar != nil {
            styles = StyleScan.scan(text)
        }
        tree = parser.parse(tree: MutableTree?.none, readBlock: rootReadBlock(for: text))
        // A full parse says little about incremental ones: those are timed from the first edit.
        lastParseDuration = .zero
        hasPendingParse = false
        inFlight = nil
        editLog = []
    }

    func rebind(_ text: NSString) {
        self.text = text
    }

    /// The host grammar reads the text with stylesheets blanked (same length and line breaks), so CSS braces
    /// never reach the TSX/JSX parser.
    private func rootReadBlock(for text: NSString) -> Parser.ReadBlock {
        guard stylesheetGrammar != nil else { return TextChunks.readBlock(for: text) }
        let contents = styles.contents
        return TextChunks.readBlock(for: text) { buffer, location in
            StyleScan.blank(contents, in: buffer, at: location)
        }
    }

    private func sameLengthEdit(over range: NSRange) -> InputEdit {
        InputEdit(
            startByte: range.location * 2, oldEndByte: range.upperBound * 2, newEndByte: range.upperBound * 2,
            startPoint: lines.point(at: range.location), oldEndPoint: lines.point(at: range.upperBound),
            newEndPoint: lines.point(at: range.upperBound))
    }

    /// Edits the root tree, logging the edit while a background reparse is in flight.
    private func edit(_ tree: MutableTree, _ edit: InputEdit, replacing oldRange: NSRange, with length: Int) {
        tree.edit(edit)
        if inFlight != nil { editLog.append((edit, oldRange, length)) }
    }

    func applyEdit(replacing oldRange: NSRange, with replacementLength: Int, in newText: NSString) -> [NSRange] {
        guard let oldTree = tree else {
            setText(newText)
            return [NSRange(location: 0, length: newText.length)]
        }
        let newEnd = oldRange.location + replacementLength
        let startPoint = lines.point(at: oldRange.location)
        let oldEndPoint = lines.point(at: oldRange.upperBound)
        lines.applyEdit(oldRange: oldRange, replacementLength: replacementLength, newText: newText)
        let edit = InputEdit(
            startByte: oldRange.location * 2,
            oldEndByte: oldRange.upperBound * 2,
            newEndByte: newEnd * 2,
            startPoint: startPoint,
            oldEndPoint: oldEndPoint,
            newEndPoint: lines.point(at: newEnd)
        )
        text = newText

        // Whole edited lines: predicates (`#match? "^[A-Z]"`) can change a token's kind beyond the typed text.
        var changed = [lines.lineRange(covering: NSRange(location: oldRange.location, length: replacementLength), length: newText.length)]
        self.edit(oldTree, edit, replacing: oldRange, with: replacementLength)
        changed += injections.applyEdit(edit)
        if stylesheetGrammar != nil {
            // Opening or closing a <style> block blanks or reveals text away from the edit: report those spans
            // to tree-sitter as same-length replacements.
            let old = styles
            styles = StyleScan.scan(newText)
            for range in StyleScan.maskChanges(
                old: old.contents, new: styles.contents, replacing: oldRange, with: replacementLength)
            {
                let maskEdit = sameLengthEdit(over: range)
                self.edit(oldTree, maskEdit, replacing: range, with: range.length)
                changed += injections.applyEdit(maskEdit)
                changed.append(range)
            }
            // The stylesheet layers read `$references` neutralized, so a reference that appears or goes away
            // (an unterminated `/*` hides every later one in its block) changes their text away from the edit.
            // The host tree sees those spans blanked either way: only the layers are told.
            for range in StyleScan.maskChanges(
                old: old.references, new: styles.references, replacing: oldRange, with: replacementLength)
            {
                changed += injections.applyEdit(sameLengthEdit(over: range))
                changed.append(range)
            }
        }
        if let threshold = deferredParseThreshold, lastParseDuration >= threshold {
            hasPendingParse = true
        } else {
            changed += reparse(oldTree)
        }
        let all = NSRange(location: 0, length: newText.length)
        return normalized(changed.compactMap { $0.clipped(to: all) })
    }

    func parsePending() -> [NSRange] {
        guard let job = beginPendingParse() else { return [] }
        return finishPendingParse(job.run()) ?? []
    }

    func beginPendingParse() -> PendingParse? {
        guard hasPendingParse, let tree, let base = tree.copy() else { return nil }
        lastParseID += 1
        inFlight = lastParseID
        editLog = []
        let text = self.text
        let length = text.length
        let units = [unichar](unsafeUninitializedCapacity: length) { buffer, count in
            if length > 0 { text.getCharacters(buffer.baseAddress!, range: NSRange(location: 0, length: length)) }
            count = length
        }
        return PendingParse(
            id: lastParseID, language: grammar.language, base: base, units: units,
            masks: stylesheetGrammar != nil ? styles.contents : nil)
    }

    func finishPendingParse(_ result: ParsedTree) -> [NSRange]? {
        guard result.id == inFlight else { return nil }
        defer {
            inFlight = nil
            editLog = []
        }
        // A failed parse leaves the edited tree and the pending reparse as they were.
        guard let installed = result.tree?.mutableCopy() else { return nil }
        var changed = result.changed
        for entry in editLog {
            installed.edit(entry.edit)
            changed = changed.map { SyntaxHighlighter.map($0, replacing: entry.oldRange, with: entry.length) }
        }
        tree = installed
        lastParseDuration = result.duration
        hasPendingParse = !editLog.isEmpty
        let all = NSRange(location: 0, length: text.length)
        return normalized(changed.compactMap { $0.clipped(to: all) })
    }

    /// Parses the edited `oldTree` against the current text, timing it; returns tree-sitter's changed ranges.
    private func reparse(_ oldTree: MutableTree) -> [NSRange] {
        let clock = ContinuousClock()
        let start = clock.now
        var changed: [NSRange] = []
        if let newTree = parser.parse(tree: oldTree, readBlock: rootReadBlock(for: text)) {
            changed = newTree.changedRanges(from: oldTree).map { $0.bytes.range }
            tree = newTree
        }
        lastParseDuration = clock.now - start
        hasPendingParse = false
        // This tree supersedes a background reparse's.
        inFlight = nil
        editLog = []
        return changed
    }

    func tokens(in range: NSRange) -> [SyntaxToken] {
        guard let tree, let range = range.clipped(to: NSRange(location: 0, length: text.length)) else { return [] }
        let context = SwiftTreeSitter.Predicate.Context(textProvider: { [text] range, _ in Self.substring(of: text, range) })
        var collector = CaptureCollector(range: range)
        collect(tree: tree, grammar: grammar, depth: 0, layerRanges: nil, range: range, context: context, into: &collector)
        if let css = stylesheetGrammar {
            for block in styles.blocks {
                guard let subrange = block.content.clipped(to: range), let layer = stylesheetLayer(block, css) else {
                    continue
                }
                collect(
                    tree: layer.tree, grammar: css, depth: 1, layerRanges: layer.ranges, range: subrange,
                    context: context, into: &collector)
            }
            StyleScan.forEach(styles.references, intersecting: range) { reference in
                collector.add(reference, code: Self.referenceCode, pattern: .max, capture: 0, depth: .max)
            }
        }
        injections.finishPass()
        return collector.resolve()
    }

    func foldRanges() -> [FoldRegion] {
        foldRanges(in: nil)
    }

    func foldRanges(within range: NSRange) -> [FoldRegion] {
        foldRanges(in: range)
    }

    private func foldRanges(in range: NSRange?) -> [FoldRegion] {
        guard let tree else { return [] }
        let builder = FoldBuilder(text: text, lines: lines)
        let bytes = range.map { UInt32($0.location * 2)..<UInt32($0.upperBound * 2) }
        var regions: [FoldRegion] = []
        builder.collect(tree: tree, rules: grammar.foldRules, into: &regions, within: bytes)
        if let css = stylesheetGrammar {
            for block in styles.blocks where block.content.length > 0 {
                if let range, NSIntersectionRange(block.content, range).length == 0 { continue }
                guard let layer = stylesheetLayer(block, css) else { continue }
                builder.collect(tree: layer.tree, rules: css.foldRules, into: &regions, within: bytes)
            }
            injections.finishPass()
        }
        return regions
    }

    /// `$name.path` references in Lumiose stylesheets are build-time constants.
    private static let referenceCode = TokenKind.paletteIndices[.constant]!

    private func stylesheetLayer(_ block: StyleBlock, _ css: GrammarConfiguration) -> InjectionCache.Layer? {
        let content = TSRange(
            points: lines.point(at: block.content.location)..<lines.point(at: block.content.upperBound),
            bytes: UInt32(block.content.location * 2)..<UInt32(block.content.upperBound * 2))
        let references = styles.references
        return injections.layer(
            grammar: css, ranges: [content], host: UInt32(block.range.location * 2)..<UInt32(block.range.upperBound * 2),
            text: text, variant: Self.stylesheetVariant,
            transform: { buffer, location in StyleScan.neutralize(references, in: buffer, at: location) })
    }

    // MARK: - Queries

    private func collect(
        tree: MutableTree, grammar: GrammarConfiguration, depth: Int, layerRanges: [TSRange]?, range: NSRange,
        context: SwiftTreeSitter.Predicate.Context, into collector: inout CaptureCollector
    ) {
        if let query = grammar.highlights {
            let cursor = query.execute(in: tree)
            cursor.setRange(range)
            while let match = cursor.next() {
                if !match.predicates.isEmpty, !allowed(match, grammar.highlightPredicates, context) { continue }
                for capture in match.captures where capture.index < grammar.highlightCodes.count {
                    guard let code = grammar.highlightCodes[capture.index] else { continue }
                    collector.add(
                        capture.node.range, code: code, pattern: match.patternIndex, capture: capture.index, depth: depth)
                }
            }
        }

        guard depth < Self.maximumInjectionDepth, let query = grammar.injections,
            let contentCapture = grammar.injectionContentCapture
        else { return }

        var separate: [Injection] = []
        // `injection.combined` matches of one pattern and language form a single injection.
        var combined: [CombinedKey: Injection] = [:]
        let cursor = query.execute(in: tree)
        cursor.setRange(range)
        while let match = cursor.next() {
            if !match.predicates.isEmpty, !allowed(match, grammar.injectionPredicates, context) { continue }
            let pattern = grammar.injectionPatterns[match.patternIndex]
            var languageName: String?
            var nodes: [Node] = []
            var host: Range<UInt32>?
            for capture in match.captures {
                host = host.map { $0.union(capture.node.byteRange) } ?? capture.node.byteRange
                if capture.index == contentCapture {
                    nodes.append(capture.node)
                } else if capture.index == grammar.injectionLanguageCapture {
                    languageName = Self.substring(of: text, capture.node.range)
                }
            }
            // A captured language name wins over `#set! injection.language`, as in tree-sitter's highlighter.
            guard !nodes.isEmpty, let host, let name = languageName ?? pattern.language,
                let grammarName = GrammarStore.grammarName(forInjection: name.trimmingCharacters(in: .whitespaces)),
                let injected = GrammarStore.configuration(named: grammarName)
            else { continue }
            if pattern.combined {
                let key = CombinedKey(pattern: match.patternIndex, grammar: injected.name)
                var group = combined[key] ?? Injection(
                    grammar: injected, nodes: [], host: host, includeChildren: pattern.includeChildren)
                group.nodes += nodes
                group.host = group.host.union(host)
                combined[key] = group
            } else {
                separate.append(Injection(grammar: injected, nodes: nodes, host: host, includeChildren: pattern.includeChildren))
            }
        }

        let groups = combined.sorted { ($0.key.pattern, $0.key.grammar) < ($1.key.pattern, $1.key.grammar) }
        for injection in separate + groups.map(\.value) {
            let nodes = injection.nodes.sorted { $0.byteRange.lowerBound < $1.byteRange.lowerBound }
            let ranges = Self.intersect(parentRanges: layerRanges, nodes: nodes, includeChildren: injection.includeChildren)
            guard let first = ranges.first, let last = ranges.last,
                let subrange = range.clipped(to: (first.bytes.lowerBound..<last.bytes.upperBound).range),
                let layer = injections.layer(grammar: injection.grammar, ranges: ranges, host: injection.host, text: text)
            else { continue }
            collect(
                tree: layer.tree, grammar: injection.grammar, depth: depth + 1, layerRanges: ranges, range: subrange,
                context: context, into: &collector)
        }
    }

    private func allowed(
        _ match: QueryMatch, _ custom: [[CustomPredicate]], _ context: SwiftTreeSitter.Predicate.Context
    ) -> Bool {
        guard match.allowed(in: context) else { return false }
        guard match.patternIndex < custom.count, !custom[match.patternIndex].isEmpty else { return true }
        return CustomPredicate.allow(custom[match.patternIndex], match) { Self.substring(of: text, $0) }
    }

    private struct CombinedKey: Hashable {
        let pattern: Int
        let grammar: String
    }

    private struct Injection {
        let grammar: GrammarConfiguration
        var nodes: [Node]
        /// Bytes of the whole injection match (language capture included): editing them can change the language.
        var host: Range<UInt32>
        let includeChildren: Bool
    }

    private static func substring(of text: NSString, _ range: NSRange) -> String? {
        guard range.location >= 0, range.upperBound <= text.length else { return nil }
        return text.substring(with: range)
    }

    /// The ranges an injection parses: the content nodes (minus their named children unless `includeChildren`),
    /// intersected with the parent layer's ranges. A port of `intersect_ranges` from tree-sitter-highlight.
    static func intersect(parentRanges: [TSRange]?, nodes: [Node], includeChildren: Bool) -> [TSRange] {
        let everything = TSRange(
            points: Point.zero..<Point(row: UInt32.max, column: UInt32.max), bytes: 0..<UInt32.max)
        let parents = parentRanges ?? [everything]
        guard !parents.isEmpty else { return [] }
        var result: [TSRange] = []
        var parentIndex = 0
        var parent = parents[0]

        for node in nodes {
            // The node's own pieces: the gaps between its children, or the whole node.
            var pieces: [(bytes: Range<UInt32>, points: Range<Point>)] = []
            var start = (byte: node.byteRange.lowerBound, point: node.pointRange.lowerBound)
            if !includeChildren {
                // Named children only, as Neovim does (most injection queries come from nvim-treesitter): the
                // Markdown block grammar exposes inline punctuation as anonymous children of `inline`.
                for index in 0..<node.namedChildCount {
                    guard let child = node.namedChild(at: index) else { continue }
                    let childStart = (byte: child.byteRange.lowerBound, point: child.pointRange.lowerBound)
                    if childStart.byte >= start.byte {
                        pieces.append((start.byte..<childStart.byte, start.point..<max(start.point, childStart.point)))
                    }
                    start = (child.byteRange.upperBound, child.pointRange.upperBound)
                }
            }
            let end = (byte: node.byteRange.upperBound, point: node.pointRange.upperBound)
            if end.byte >= start.byte {
                pieces.append((start.byte..<end.byte, start.point..<max(start.point, end.point)))
            }

            for piece in pieces {
                var lower = (byte: piece.bytes.lowerBound, point: piece.points.lowerBound)
                let upper = (byte: piece.bytes.upperBound, point: piece.points.upperBound)
                if upper.byte < parent.bytes.lowerBound { continue }
                while parent.bytes.lowerBound <= upper.byte {
                    if parent.bytes.upperBound > lower.byte {
                        if lower.byte < parent.bytes.lowerBound {
                            lower = (parent.bytes.lowerBound, parent.points.lowerBound)
                        }
                        if parent.bytes.upperBound < upper.byte {
                            if lower.byte < parent.bytes.upperBound {
                                result.append(
                                    TSRange(
                                        points: lower.point..<max(lower.point, parent.points.upperBound),
                                        bytes: lower.byte..<parent.bytes.upperBound))
                            }
                            lower = (parent.bytes.upperBound, parent.points.upperBound)
                        } else {
                            if lower.byte < upper.byte {
                                result.append(
                                    TSRange(points: lower.point..<max(lower.point, upper.point), bytes: lower.byte..<upper.byte))
                            }
                            break
                        }
                    }
                    parentIndex += 1
                    guard parentIndex < parents.count else { return result }
                    parent = parents[parentIndex]
                }
            }
        }
        return result
    }
}

/// Injected layers keyed by grammar and included ranges. Layers an edit doesn't touch survive it (shifted when
/// they follow the edit); touched ones are dropped, but their edited trees are reused when the same grammar is
/// injected over an overlapping range again, so retyping inside a long fenced block reparses incrementally.
final class InjectionCache {
    final class Layer {
        let grammar: GrammarConfiguration
        let variant: Int
        var ranges: [TSRange]
        var host: Range<UInt32>
        var tree: MutableTree
        var lastUse: Int

        init(
            grammar: GrammarConfiguration, variant: Int, ranges: [TSRange], host: Range<UInt32>, tree: MutableTree,
            lastUse: Int
        ) {
            self.grammar = grammar
            self.variant = variant
            self.ranges = ranges
            self.host = host
            self.tree = tree
            self.lastUse = lastUse
        }

        /// The included ranges and the injection match: the bytes an edit must touch to affect the layer.
        var span: Range<UInt32> {
            guard let first = ranges.first, let last = ranges.last else { return host }
            return host.union(first.bytes.lowerBound..<last.bytes.upperBound)
        }

        var key: Key {
            Key(grammar: grammar.name, variant: variant, ranges: ranges.map(\.bytes))
        }
    }

    struct Key: Hashable {
        let grammar: String
        /// Layers of one grammar read through different transforms are never mixed up or reused for each other.
        let variant: Int
        let ranges: [Range<UInt32>]
    }

    static let capacity = 1024
    static let reusableLimit = 16

    private var layers: [Key: Layer] = [:]
    private var reusable: [Layer] = []
    private var generation = 0
    private let parser = Parser()

    var count: Int { layers.count }

    func layer(
        grammar: GrammarConfiguration, ranges: [TSRange], host: Range<UInt32>, text: NSString, variant: Int = 0,
        transform: TextChunks.Transform? = nil
    ) -> Layer? {
        let key = Key(grammar: grammar.name, variant: variant, ranges: ranges.map(\.bytes))
        if let layer = layers[key] {
            layer.lastUse = generation
            layer.host = host
            return layer
        }
        let span = ranges[0].bytes.lowerBound..<ranges[ranges.count - 1].bytes.upperBound
        var oldTree: MutableTree?
        if let index = reusable.firstIndex(where: {
            $0.grammar === grammar && $0.variant == variant && $0.span.overlaps(span)
        }) {
            oldTree = reusable.remove(at: index).tree
        }
        guard (try? parser.setLanguage(grammar.language)) != nil else { return nil }
        parser.includedRanges = ranges
        guard let tree = parser.parse(tree: oldTree, readBlock: TextChunks.readBlock(for: text, transform: transform))
        else { return nil }
        let layer = Layer(grammar: grammar, variant: variant, ranges: ranges, host: host, tree: tree, lastUse: generation)
        layers[key] = layer
        return layer
    }

    /// Applies an edit to every layer and returns the ranges (in the new text) of the layers it touched.
    func applyEdit(_ edit: InputEdit) -> [NSRange] {
        // Touched layers stay reusable across consecutive edits, as long as each edit is applied to them.
        for layer in reusable {
            layer.tree.edit(edit)
            layer.ranges = layer.tree.includedRanges
        }
        var invalidated: [NSRange] = []
        var kept: [Key: Layer] = [:]
        let delta = Int(edit.newEndByte) - Int(edit.oldEndByte)
        for layer in layers.values {
            let span = layer.span
            layer.tree.edit(edit)
            if span.upperBound < edit.startByte {
                kept[layer.key] = layer
            } else if span.lowerBound > edit.oldEndByte {
                layer.ranges = layer.tree.includedRanges
                layer.host = UInt32(Int(layer.host.lowerBound) + delta)..<UInt32(Int(layer.host.upperBound) + delta)
                kept[layer.key] = layer
            } else {
                reusable.append(layer)
                let start = Int(min(span.lowerBound, edit.startByte)) / 2
                let end = max(Int(span.upperBound) + delta, Int(edit.newEndByte)) / 2
                invalidated.append(NSRange(location: start, length: max(0, end - start)))
            }
        }
        layers = kept
        if reusable.count > Self.reusableLimit {
            reusable.removeFirst(reusable.count - Self.reusableLimit)
        }
        return invalidated
    }

    /// Ends one `tokens(in:)` pass; drops the least recently used layers beyond the capacity.
    func finishPass() {
        generation += 1
        guard layers.count > Self.capacity else { return }
        let stale = layers.values.sorted { $0.lastUse < $1.lastUse }.prefix(layers.count - Self.capacity * 3 / 4)
        for layer in stale { layers[layer.key] = nil }
    }

    func removeAll() {
        layers.removeAll()
        reusable.removeAll()
    }
}

/// Collects highlight captures for one range and resolves overlaps by painting: larger captures first, then
/// smaller (inner) ones over them; for the same range, shallower layers and earlier patterns first, so deeper
/// layers and later patterns win, matching tree-sitter's highlighter.
struct CaptureCollector {
    /// Paint code for `@none`.
    static let clear: Int16 = -1

    private struct Capture {
        let start: Int
        let end: Int
        let length: Int
        let code: Int16
        let depth: Int
        let pattern: Int
        let capture: Int
    }

    let range: NSRange
    private var captures: [Capture] = []

    init(range: NSRange) {
        self.range = range
    }

    mutating func add(_ nodeRange: NSRange, code: Int16, pattern: Int, capture: Int, depth: Int) {
        guard let clipped = nodeRange.clipped(to: range) else { return }
        captures.append(
            Capture(
                start: clipped.location - range.location, end: clipped.upperBound - range.location,
                length: nodeRange.length, code: code, depth: depth, pattern: pattern, capture: capture))
    }

    func resolve() -> [SyntaxToken] {
        guard !captures.isEmpty, range.length > 0 else { return [] }
        let ordered = captures.sorted {
            if $0.length != $1.length { return $0.length > $1.length }
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            if $0.pattern != $1.pattern { return $0.pattern < $1.pattern }
            return $0.capture < $1.capture
        }
        var paint = [Int16](repeating: Self.clear, count: range.length)
        paint.withUnsafeMutableBufferPointer { buffer in
            for capture in ordered {
                buffer[capture.start..<capture.end].update(repeating: capture.code)
            }
        }
        var tokens: [SyntaxToken] = []
        var runStart = 0
        for index in 1...paint.count {
            if index == paint.count || paint[index] != paint[runStart] {
                let code = paint[runStart]
                if code != Self.clear {
                    tokens.append(
                        SyntaxToken(
                            range: NSRange(location: range.location + runStart, length: index - runStart),
                            kind: TokenKind.fixed[Int(code)]))
                }
                runStart = index
            }
        }
        return tokens
    }
}

extension Range where Bound == UInt32 {
    func union(_ other: Range<UInt32>) -> Range<UInt32> {
        Swift.min(lowerBound, other.lowerBound)..<Swift.max(upperBound, other.upperBound)
    }
}
