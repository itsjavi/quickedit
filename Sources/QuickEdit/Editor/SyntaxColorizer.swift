import AppKit
import QuickEditSyntax

/// Colours the editor's visible text with tree-sitter tokens, as layout-manager temporary attributes: the text
/// storage, undo and the file never change, and only what's on screen is coloured (decision-2).
final class SyntaxColorizer {
    /// Files longer than this (UTF-16 units, ~4 MB) open without highlighting.
    static let maximumLength = 4_000_000

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

    /// Bumped by every reset, so a late query compilation for an older language is ignored.
    private var generation = 0

    /// Starts over with `language` and the current text (on load, revert or a language change).
    func reset(language: Language) {
        self.language = language
        generation += 1
        highlighter = nil
        clearColors()
        guard let textView, language.hasHighlighting, (textView.string as NSString).length <= Self.maximumLength else { return }
        // Compiling a grammar's queries can take ~200 ms (Swift) the first time: do it off the main thread.
        let current = generation
        Task.detached(priority: .userInitiated) {
            SyntaxHighlighter.prepare(language)
            await MainActor.run { [weak self] in self?.start(language, generation: current) }
        }
    }

    private func start(_ language: Language, generation current: Int) {
        guard current == generation, let textView else { return }
        let text = textView.string as NSString
        guard text.length <= Self.maximumLength else { return }
        let highlighter = SyntaxHighlighter(language: language)
        highlighter.setText(text)
        self.highlighter = highlighter
        colorVisibleRange()
    }

    /// Call from the text storage's `didProcessEditing` for character edits.
    func textDidEdit(editedRange: NSRange, changeInLength delta: Int) {
        guard let textView, let highlighter else { return }
        let text = textView.string as NSString
        guard text.length <= Self.maximumLength else {
            self.highlighter = nil
            clearColors()
            return
        }
        let oldRange = NSRange(location: editedRange.location, length: editedRange.length - delta)
        highlighter.applyEdit(replacing: oldRange, with: editedRange.length, in: text)
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
        let length = (textView.string as NSString).length
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
        let length = (textView.string as NSString).length
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
        coloredRange = NSRange(location: NSNotFound, length: 0)
    }

    /// Tokens of a range (Test-build hooks).
    func tokens(in range: NSRange) -> [SyntaxToken] {
        highlighter?.tokens(in: range) ?? []
    }
}
