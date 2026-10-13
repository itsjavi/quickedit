import AppKit
import QuickEditSyntax

/// Colours the editor's visible text with tree-sitter tokens, as layout-manager temporary attributes: the text
/// storage, undo and the file never change, and only what's on screen is coloured (decision-2).
final class SyntaxColorizer {
    /// Files longer than this (UTF-16 units, ~16 MB) open without highlighting. Larger ones parse off the main
    /// thread and reparse when typing pauses, but tree-sitter's tree costs memory in proportion.
    static let maximumLength = 16_000_000

    private(set) var language: Language
    private var highlighter: SyntaxHighlighter?
    private weak var textView: NSTextView?
    /// The character range coloured last; recoloured after scrolling past it or editing inside it.
    private var coloredRange = NSRange(location: NSNotFound, length: 0)
    private var isRecolorScheduled = false

    init(textView: NSTextView, language: Language) {
        self.textView = textView
        self.language = language
    }

    var isActive: Bool { highlighter != nil }

    /// The live storage string: fast UTF-16 access and no copy (the highlighter keeps it and reads lazily).
    private var liveText: NSString? { textView?.textStorage?.mutableString }

    /// Bumped by every reset, so a late query compilation for an older language is ignored.
    private var generation = 0

    /// Starts over with `language` and the current text (on load, revert or a language change). The first parse
    /// runs off the main thread on a snapshot, so a large file shows and scrolls at once and its colours follow.
    func reset(language: Language) {
        self.language = language
        generation += 1
        highlighter = nil
        pendingParse?.cancel()
        clearColors()
        guard let text = liveText, language.hasHighlighting, text.length <= Self.maximumLength else { return }
        let current = generation
        let snapshot = Snapshot(text: text.copy() as! NSString)
        editsSinceReset = 0
        Task.detached(priority: .userInitiated) {
            // Compiling a grammar's queries can take ~200 ms (Swift) the first time, and parsing a few MB as long.
            SyntaxHighlighter.prepare(language)
            let highlighter = SyntaxHighlighter(language: language)
            highlighter.tracksTokenChanges = false  // every edit recolours the visible range anyway
            highlighter.deferredParseThreshold = .milliseconds(8)
            highlighter.setText(snapshot.text)
            await MainActor.run { [weak self] in self?.install(highlighter, generation: current) }
        }
    }

    /// An immutable copy of the text for the background parse.
    private nonisolated struct Snapshot: @unchecked Sendable {
        let text: NSString
    }

    /// Edits since the last reset: one made during the background parse makes its snapshot stale.
    private var editsSinceReset = 0

    private func install(_ highlighter: SyntaxHighlighter, generation current: Int) {
        guard current == generation, let text = liveText else { return }
        guard editsSinceReset == 0 else {
            reset(language: language)
            return
        }
        highlighter.rebind(text)
        self.highlighter = highlighter
        colorVisibleRange()
    }

    /// Call from the text storage's `didProcessEditing` for character edits.
    func textDidEdit(editedRange: NSRange, changeInLength delta: Int) {
        editsSinceReset += 1
        guard let text = liveText, let highlighter else { return }
        guard text.length <= Self.maximumLength else {
            self.highlighter = nil
            clearColors()
            return
        }
        let oldRange = NSRange(location: editedRange.location, length: editedRange.length - delta)
        highlighter.applyEdit(replacing: oldRange, with: editedRange.length, in: text)
        if highlighter.hasPendingParse { schedulePendingParse() }
        // An edit can change tokens far below it (an opened comment or string): recolour what's visible.
        coloredRange = NSRange(location: NSNotFound, length: 0)
        scheduleRecolor()
    }

    /// Recolours after scrolling or resizing when the visible range moved outside what's coloured.
    func visibleRangeDidChange() {
        guard isActive, let visible = visibleCharacterRange() else { return }
        if coloredRange.location == NSNotFound || NSIntersectionRange(visible, coloredRange).length < visible.length {
            colorVisibleRange()
        }
    }

    private var pendingParse: DispatchWorkItem?

    /// A large file's reparse waits until typing pauses; then what's visible is recoloured.
    private func schedulePendingParse() {
        pendingParse?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let highlighter = self.highlighter, highlighter.hasPendingParse else { return }
                highlighter.parsePending()
                self.coloredRange = NSRange(location: NSNotFound, length: 0)
                self.colorVisibleRange()
                self.textView?.enclosingScrollView?.verticalRulerView?.needsDisplay = true  // fold arrows
            }
        }
        pendingParse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func scheduleRecolor() {
        guard !isRecolorScheduled else { return }
        isRecolorScheduled = true
        // After the text system finishes processing the edit (temporary attributes can't change mid-edit).
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.isRecolorScheduled = false
                self?.colorVisibleRange()
            }
        }
    }

    private func visibleCharacterRange() -> NSRange? {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return nil }
        // A screen above and below, so scrolling a little doesn't show uncoloured text.
        var rect = textView.visibleRect
        rect = rect.insetBy(dx: 0, dy: -rect.height)
        let glyphs = layoutManager.glyphRange(forBoundingRect: rect, in: container)
        return layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
    }

    func colorVisibleRange() {
        guard let textView, let layoutManager = textView.layoutManager, let highlighter, let range = visibleCharacterRange() else { return }
        let length = textView.textStorage?.length ?? 0
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: length))
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: clamped)
        for token in highlighter.tokens(in: clamped) {
            guard let color = SyntaxPalette.color(for: token.kind) else { continue }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: token.range)
        }
        coloredRange = clamped
    }

    private func clearColors() {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        let length = textView.textStorage?.length ?? 0
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
        coloredRange = NSRange(location: NSNotFound, length: 0)
    }

    /// Foldable regions as the character ranges they hide (empty for languages without folding).
    func foldRegions() -> [NSRange] {
        highlighter?.foldRanges().map(\.hidden) ?? []
    }

    /// The hidden ranges of the regions starting in `range`, without computing the others (the gutter's markers).
    func foldRegions(startingIn range: NSRange) -> [NSRange] {
        highlighter?.foldRanges(startingIn: range).map(\.hidden) ?? []
    }

    /// Tokens of a range (Test-build hooks).
    func tokens(in range: NSRange) -> [SyntaxToken] {
        highlighter?.tokens(in: range) ?? []
    }
}
