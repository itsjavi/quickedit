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
        parseTask?.cancel()  // its result is ignored (generation); the parse itself can't be interrupted
        parseTask = nil
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

    /// After scrolling or resizing, colours what's about to show if it isn't yet: a screen above and below the
    /// visible text, extended to three in one go. Only text not coloured yet is touched, because changing colours
    /// redraws that text, and redrawing what AppKit already drew ahead for a fast scroll shows up as late content.
    func visibleRangeDidChange() {
        guard isActive, let needed = visibleCharacterRange(screens: 1) else { return }
        if coloredRange.location != NSNotFound, NSIntersectionRange(needed, coloredRange).length == needed.length { return }
        guard let target = visibleCharacterRange(screens: 3) else { return }
        guard coloredRange.location != NSNotFound, target.location <= NSMaxRange(coloredRange),
              NSMaxRange(target) >= coloredRange.location
        else {
            color(target)
            coloredRange = target
            return
        }
        if target.location < coloredRange.location {
            color(NSRange(location: target.location, length: coloredRange.location - target.location))
        }
        if NSMaxRange(target) > NSMaxRange(coloredRange) {
            color(NSRange(location: NSMaxRange(coloredRange), length: NSMaxRange(target) - NSMaxRange(coloredRange)))
        }
        coloredRange = NSUnionRange(coloredRange, target)
    }

    private var pendingParse: DispatchWorkItem?
    /// The catch-up reparse running off the main thread.
    private var parseTask: Task<Void, Never>?

    /// A large file's reparse waits until typing pauses; then it runs off the main thread and what's visible is
    /// recoloured.
    private func schedulePendingParse() {
        pendingParse?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.startPendingParse() }
        }
        pendingParse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// One reparse at a time, on a snapshot: typing goes on meanwhile, and the edits are replayed onto the new
    /// tree, which leaves a reparse pending for the next pause.
    private func startPendingParse() {
        guard parseTask == nil, let highlighter else { return }
        let start = ContinuousClock.now
        guard let job = highlighter.beginPendingParse() else { return }
        #if DEBUG
            catchUpTimings.append(ContinuousClock.now - start)
        #endif
        let current = generation
        parseTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { job.run() }.value
            self?.finishPendingParse(result, generation: current)
        }
    }

    private func finishPendingParse(_ result: ParsedTree, generation current: Int) {
        guard current == generation else { return }
        parseTask = nil
        guard let highlighter else { return }
        let start = ContinuousClock.now
        if highlighter.finishPendingParse(result) != nil {
            coloredRange = NSRange(location: NSNotFound, length: 0)
            colorVisibleRange()
            textView?.enclosingScrollView?.verticalRulerView?.needsDisplay = true  // fold arrows
            #if DEBUG
                catchUpTimings.append(ContinuousClock.now - start)
            #endif
        }
        // Edits made during the parse (or a failed parse) leave a reparse waiting.
        if highlighter.hasPendingParse { schedulePendingParse() }
    }

    #if DEBUG
        /// Main-thread time of each catch-up step (starting a reparse; installing it and recolouring), for
        /// `debug/editor-bench`.
        var catchUpTimings: [Duration] = []
        /// A reparse is waiting, scheduled or running.
        var isCatchingUp: Bool { parseTask != nil || highlighter?.hasPendingParse == true }
    #endif

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

    /// The visible text plus `screens` screen heights above and below it.
    private func visibleCharacterRange(screens: CGFloat) -> NSRange? {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return nil }
        var rect = textView.visibleRect
        rect = rect.insetBy(dx: 0, dy: -rect.height * screens)
        let glyphs = layoutManager.glyphRange(forBoundingRect: rect, in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        return NSIntersectionRange(characters, NSRange(location: 0, length: textView.textStorage?.length ?? 0))
    }

    /// Recolours the visible text and a screen around it (after an edit, a reparse or showing the editor again).
    func colorVisibleRange() {
        guard highlighter != nil, let range = visibleCharacterRange(screens: 1) else { return }
        color(range)
        coloredRange = range
    }

    private func color(_ range: NSRange) {
        guard let layoutManager = textView?.layoutManager, let highlighter, range.length > 0 else { return }
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        for token in highlighter.tokens(in: range) {
            guard let color = SyntaxPalette.color(for: token.kind) else { continue }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: token.range)
        }
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
