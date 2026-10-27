import Foundation

/// Highlights one document. Feed it the text with `setText(_:)`, report every change with
/// `applyEdit(replacing:with:in:)` (it reparses incrementally) and ask for the tokens of the visible range.
///
/// All offsets are UTF-16 (`NSString`) offsets. The highlighter keeps a reference to the last text it was given
/// and reads from it lazily (tree-sitter reads chunks), so call `applyEdit` right after each change and before
/// the next `tokens(in:)`. Not thread-safe: use one highlighter from one thread (the main thread in the app).
public final class SyntaxHighlighter {
    public let language: Language
    private let engine: any HighlightEngine
    /// The most recently requested ranges and their tokens (latest last). Edits re-highlight them to report exact
    /// changes there, and a repeated request for the same range is answered from here.
    private var recent: [(range: NSRange, tokens: [SyntaxToken])] = []
    private static let recentLimit = 2
    /// `foldRanges()` until the next edit.
    private var folds: [FoldRegion]?
    private static let recentMaximumLength = 64 * 1024

    /// Whether `applyEdit` diffs the tokens of recently queried ranges to report exact changes. That queries
    /// those ranges again on every edit; a caller that recolours what's visible after each edit anyway (the
    /// editor) turns it off.
    public var tracksTokenChanges = true

    public init(language: Language) {
        self.language = language
        switch language.highlighting {
        case .none:
            engine = PlainTextEngine()
        case .delimited(let delimiter):
            engine = DelimitedEngine(delimiter: delimiter)
        case .lexer(let lexer):
            engine = LexerEngine(lexer: lexer)
        case .grammar(let name):
            if let grammar = GrammarStore.configuration(named: name) {
                engine = TreeSitterEngine(grammar: grammar)
            } else {
                engine = PlainTextEngine()
            }
        case .styled(let host):
            if let grammar = GrammarStore.configuration(named: host), let css = GrammarStore.configuration(named: "css") {
                engine = TreeSitterEngine(grammar: grammar, stylesheets: css)
            } else {
                engine = PlainTextEngine()
            }
        }
    }

    /// Replaces the whole text and parses it from scratch.
    public func setText(_ text: NSString) {
        recent.removeAll()
        folds = nil
        engine.setText(text)
    }

    /// After `setText` with a snapshot (parsed off the main thread), switches to the live text with the same
    /// contents, so later edits and token queries read it.
    public func rebind(_ text: NSString) {
        engine.rebind(text)
    }

    /// With a threshold, an edit made after an incremental parse that took at least that long only adjusts the
    /// tree: the reparse waits for `parsePending()`, which the editor calls once typing pauses, so typing in a large
    /// file stays fast. Nil (the default) parses after every edit. Set it before `setText(_:)`: a full parse that
    /// takes at least as long leaves a warm-up reparse waiting (`hasPendingParse`), since the first incremental
    /// parse of some grammars (Markdown) costs nearly as much as the full one; run it before the first edit.
    public var deferredParseThreshold: Duration? {
        didSet { (engine as? TreeSitterEngine)?.deferredParseThreshold = deferredParseThreshold }
    }

    /// An edit's reparse is waiting (see `deferredParseThreshold`).
    public var hasPendingParse: Bool { engine.hasPendingParse }

    /// Runs the waiting reparse; returns the ranges whose tokens may have changed.
    @discardableResult
    public func parsePending() -> [NSRange] {
        guard engine.hasPendingParse else { return [] }
        recent.removeAll()
        folds = nil
        return engine.parsePending()
    }

    /// Starts the waiting reparse as a job to run off the main thread (`PendingParse.run()`), then hand its result
    /// to `finishPendingParse(_:)`. Meanwhile edits and queries go on as before, on the edited old tree. Nil when no
    /// reparse is waiting (or the language doesn't defer).
    public func beginPendingParse() -> PendingParse? {
        engine.beginPendingParse()
    }

    /// Installs a background reparse, replaying the edits made since `beginPendingParse()` onto its tree (they
    /// keep `hasPendingParse` set). Returns the ranges whose tokens may have changed, or nil when the result was
    /// superseded (by a newer job, `setText` or a synchronous reparse) or the parse failed.
    @discardableResult
    public func finishPendingParse(_ result: ParsedTree) -> [NSRange]? {
        guard let changed = engine.finishPendingParse(result) else { return nil }
        recent.removeAll()
        folds = nil
        return changed
    }

    /// Reports that `oldRange` (in the previous text) was replaced by `replacementLength` UTF-16 units, giving
    /// `newText`. Reparses incrementally and returns the sorted, merged ranges of `newText` whose tokens may have
    /// changed: the edited lines, tree-sitter's changed ranges and touched injections, plus the exact differences
    /// within the ranges requested recently (the visible range), which catch context-dependent query matches
    /// tree-sitter's changed ranges miss.
    @discardableResult
    public func applyEdit(replacing oldRange: NSRange, with replacementLength: Int, in newText: NSString) -> [NSRange] {
        folds = nil
        var changed = engine.applyEdit(replacing: oldRange, with: replacementLength, in: newText)
        let inserted = NSRange(location: oldRange.location, length: replacementLength)
        if !engine.isPlainText {
            changed.append(inserted)
        }
        let previous = recent
        recent.removeAll()
        let all = NSRange(location: 0, length: newText.length)
        for (range, oldTokens) in previous {
            guard let mapped = Self.map(range, replacing: oldRange, with: replacementLength).clipped(to: all) else {
                continue
            }
            let newTokens = engine.tokens(in: mapped)
            changed += Self.differences(
                old: oldTokens.flatMap { Self.map($0, replacing: oldRange, with: replacementLength) },
                new: newTokens, in: mapped)
            remember(mapped, newTokens)
        }
        return normalized(changed.compactMap { $0.clipped(to: all) })
    }

    /// Tokens intersecting `range`, clipped to it, sorted by location and non-overlapping (the innermost
    /// capture wins; for the same node the last query pattern wins, as in tree-sitter's highlighter).
    public func tokens(in range: NSRange) -> [SyntaxToken] {
        if let index = recent.firstIndex(where: { $0.range == range }) {
            let entry = recent.remove(at: index)
            recent.append(entry)
            return entry.tokens
        }
        let tokens = engine.tokens(in: range)
        remember(range, tokens)
        return tokens
    }

    /// Foldable regions of the current text, sorted by location (outer before inner), possibly nested. Computed
    /// from the syntax tree (JSON, CSS, YAML, TOML, JavaScript/TypeScript/TSX and Lumiose, Go, Rust, Python,
    /// Swift, Markdown, HTML, XML) and cached until the next edit; empty for other languages.
    public func foldRanges() -> [FoldRegion] {
        if let folds { return folds }
        let computed = FoldBuilder.normalized(engine.foldRanges())
        folds = computed
        return computed
    }

    /// The foldable regions whose hidden range starts in `range`: the gutter's markers for the visible lines,
    /// without walking the whole tree after every edit of a large file.
    public func foldRanges(startingIn range: NSRange) -> [FoldRegion] {
        let regions = folds ?? FoldBuilder.normalized(engine.foldRanges(within: range))
        return regions.filter { NSLocationInRange($0.hidden.location, range) }
    }

    /// Compiles the queries of `language`'s grammar ahead of time so the first `SyntaxHighlighter` doesn't pay
    /// for it. Thread-safe; call it from a background task.
    public static func prepare(_ language: Language) {
        switch language.highlighting {
        case .grammar(let name):
            _ = GrammarStore.configuration(named: name)
        case .styled(let host):
            _ = GrammarStore.configuration(named: host)
            _ = GrammarStore.configuration(named: "css")
        case .none, .delimited, .lexer:
            break
        }
    }

    // MARK: - Recent ranges

    private func remember(_ range: NSRange, _ tokens: [SyntaxToken]) {
        guard tracksTokenChanges, range.length > 0, range.length <= Self.recentMaximumLength, !engine.isPlainText else { return }
        recent.removeAll { $0.range == range }
        recent.append((range, tokens))
        if recent.count > Self.recentLimit {
            recent.removeFirst(recent.count - Self.recentLimit)
        }
    }

    /// `range` in the new text after `oldRange` was replaced by `length` units; ranges touching the edit grow to
    /// cover the replacement.
    static func map(_ range: NSRange, replacing oldRange: NSRange, with length: Int) -> NSRange {
        let delta = length - oldRange.length
        if range.upperBound < oldRange.location {
            return range
        }
        if range.location > oldRange.upperBound {
            return NSRange(location: range.location + delta, length: range.length)
        }
        let start = min(range.location, oldRange.location)
        let end = max(range.upperBound + delta, oldRange.location + length, start)
        return NSRange(location: start, length: end - start)
    }

    /// The parts of an old token outside the edit, in new coordinates.
    static func map(_ token: SyntaxToken, replacing oldRange: NSRange, with length: Int) -> [SyntaxToken] {
        let delta = length - oldRange.length
        let range = token.range
        var parts: [SyntaxToken] = []
        if range.location < oldRange.location {
            let end = min(range.upperBound, oldRange.location)
            parts.append(SyntaxToken(range: NSRange(location: range.location, length: end - range.location), kind: token.kind))
        }
        if range.upperBound > oldRange.upperBound {
            let start = max(range.location, oldRange.upperBound)
            parts.append(
                SyntaxToken(range: NSRange(location: start + delta, length: range.upperBound - start), kind: token.kind))
        }
        return parts
    }

    /// Ranges within `range` where the kinds of `old` and `new` differ.
    static func differences(old: [SyntaxToken], new: [SyntaxToken], in range: NSRange) -> [NSRange] {
        var oldKinds = [TokenKind?](repeating: nil, count: range.length)
        var newKinds = [TokenKind?](repeating: nil, count: range.length)
        func paint(_ tokens: [SyntaxToken], into kinds: inout [TokenKind?]) {
            for token in tokens {
                guard let clipped = token.range.clipped(to: range) else { continue }
                for index in (clipped.location - range.location)..<(clipped.upperBound - range.location) {
                    kinds[index] = token.kind
                }
            }
        }
        paint(old, into: &oldKinds)
        paint(new, into: &newKinds)
        var result: [NSRange] = []
        var runStart: Int?
        for index in 0...range.length {
            let differs = index < range.length && oldKinds[index] != newKinds[index]
            if differs, runStart == nil {
                runStart = index
            } else if !differs, let start = runStart {
                result.append(NSRange(location: range.location + start, length: index - start))
                runStart = nil
            }
        }
        return result
    }
}

@available(*, unavailable)
extension SyntaxHighlighter: Sendable {}

protocol HighlightEngine: AnyObject {
    /// Plain text never has tokens, so there's nothing to track or report.
    var isPlainText: Bool { get }
    func setText(_ text: NSString)
    func applyEdit(replacing oldRange: NSRange, with replacementLength: Int, in newText: NSString) -> [NSRange]
    func tokens(in range: NSRange) -> [SyntaxToken]
    func foldRanges() -> [FoldRegion]
    /// At least the regions of nodes that overlap `range` (the visible text), without walking the rest of the tree.
    func foldRanges(within range: NSRange) -> [FoldRegion]
    /// Points the engine at `text` without parsing it: the same contents it was parsed from (a snapshot).
    func rebind(_ text: NSString)
    /// An edit's reparse is waiting (see `SyntaxHighlighter.deferredParseThreshold`).
    var hasPendingParse: Bool { get }
    /// Runs the waiting reparse; returns the ranges whose tokens may have changed.
    func parsePending() -> [NSRange]
    /// The waiting reparse as a job for another thread (see `SyntaxHighlighter.beginPendingParse()`).
    func beginPendingParse() -> PendingParse?
    func finishPendingParse(_ result: ParsedTree) -> [NSRange]?
}

extension HighlightEngine {
    var hasPendingParse: Bool { false }
    func parsePending() -> [NSRange] { [] }
    func beginPendingParse() -> PendingParse? { nil }
    func finishPendingParse(_ result: ParsedTree) -> [NSRange]? { nil }
}

final class PlainTextEngine: HighlightEngine {
    var isPlainText: Bool { true }

    func setText(_ text: NSString) {}

    func rebind(_ text: NSString) {}

    func applyEdit(replacing oldRange: NSRange, with replacementLength: Int, in newText: NSString) -> [NSRange] {
        []
    }

    func tokens(in range: NSRange) -> [SyntaxToken] {
        []
    }
}

extension NSRange {
    /// The intersection, or nil when the ranges don't overlap (touching empty ranges count as not overlapping).
    func clipped(to other: NSRange) -> NSRange? {
        let start = Swift.max(location, other.location)
        let end = Swift.min(upperBound, other.upperBound)
        return start < end ? NSRange(location: start, length: end - start) : nil
    }
}

/// Sorts and merges overlapping or adjacent ranges.
func normalized(_ ranges: [NSRange]) -> [NSRange] {
    let sorted = ranges.filter { $0.length > 0 }.sorted { $0.location < $1.location }
    var result: [NSRange] = []
    for range in sorted {
        if let last = result.last, range.location <= last.upperBound {
            result[result.count - 1] = NSRange(
                location: last.location, length: Swift.max(last.upperBound, range.upperBound) - last.location)
        } else {
            result.append(range)
        }
    }
    return result
}

extension HighlightEngine {
    var isPlainText: Bool { false }
    func foldRanges() -> [FoldRegion] { [] }
    func foldRanges(within range: NSRange) -> [FoldRegion] { foldRanges() }
}
