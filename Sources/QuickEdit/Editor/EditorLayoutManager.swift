import AppKit
import QuickEditCore

/// TextKit 1 layout manager for the editor. With `showsInvisibles` it draws spaces as ·, tabs as →, and line endings
/// by kind (LF ¬, CRLF ↵, CR ←) in a faint colour over the text, without changing the text or its layout.
/// (NSLayoutManager's own `showsInvisibleCharacters` glyphs look poor and can't be styled.)
nonisolated final class EditorLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    override init() {
        super.init()
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: Folding

    /// Folded (hidden) character ranges, sorted by location; nested ones may be inside others.
    private(set) var foldedRanges: [NSRange] = []
    /// Width of the ⋯ placeholder that stands in for a folded range.
    var foldPlaceholderWidth: CGFloat = 26

    /// The outermost folded range containing `index`.
    func fold(containing index: Int) -> NSRange? {
        foldedRanges.first { NSLocationInRange(index, $0) }
    }

    /// Replaces the folded ranges and re-lays out what changed. The text never changes.
    func setFoldedRanges(_ ranges: [NSRange]) {
        let old = foldedRanges
        foldedRanges = ranges.sorted { $0.location < $1.location }
        guard let length = textStorage?.length else { return }
        for range in Set(old.map(Box.init)).symmetricDifference(Set(foldedRanges.map(Box.init))).map(\.range) {
            let clamped = NSIntersectionRange(range, NSRange(location: 0, length: length))
            invalidateGlyphs(forCharacterRange: clamped, changeInLength: 0, actualCharacterRange: nil)
            invalidateLayout(forCharacterRange: clamped, actualCharacterRange: nil)
        }
    }

    /// Updates fold positions after an edit that didn't touch them: their glyphs move with the text, so nothing
    /// needs re-laying out.
    func replaceFoldedRangesSilently(_ ranges: [NSRange]) {
        foldedRanges = ranges.sorted { $0.location < $1.location }
    }

    /// Regenerates glyphs and layout for `range` (after folds inside it went away during an edit).
    func invalidateFoldLayout(_ range: NSRange) {
        invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
        invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
    }

    private struct Box: Hashable {
        let range: NSRange
        func hash(into hasher: inout Hasher) { hasher.combine(range.location); hasher.combine(range.length) }
        static func == (a: Box, b: Box) -> Bool { NSEqualRanges(a.range, b.range) }
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard !foldedRanges.isEmpty, glyphRange.length > 0 else { return 0 }
        let first = characterIndexes[0]
        let last = characterIndexes[glyphRange.length - 1]
        guard foldedRanges.contains(where: { $0.location <= last && NSMaxRange($0) > first }) else { return 0 }
        var changed = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        for index in 0..<glyphRange.length {
            guard let fold = fold(containing: characterIndexes[index]) else { continue }
            // The first hidden character becomes the ⋯ placeholder; the rest take no space at all.
            changed[index] = characterIndexes[index] == fold.location ? .controlCharacter : .null
        }
        changed.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(glyphs, properties: buffer.baseAddress!, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction, forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        guard let fold = fold(containing: charIndex) else { return action }
        // Hidden line breaks don't break lines, so a folded block shows as `{ ⋯ }` on one line.
        return charIndex == fold.location ? .whitespace : .zeroAdvancement
    }

    func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer, proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex: Int) -> NSRect {
        NSRect(x: glyphPosition.x, y: 0, width: fold(containing: characterIndex)?.location == characterIndex ? foldPlaceholderWidth : 0, height: proposedRect.height)
    }

    /// Draws the ⋯ pill where each visible folded range starts.
    private func drawFoldPlaceholders(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard !foldedRanges.isEmpty else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for fold in foldedRanges where NSLocationInRange(fold.location, characters) && self.fold(containing: fold.location) == fold {
            let glyph = glyphIndexForCharacter(at: fold.location)
            guard isValidGlyphIndex(glyph), let container = textContainer(forGlyphAt: glyph, effectiveRange: nil) else { continue }
            let box = boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let pill = NSRect(x: origin.x + box.minX + 3, y: origin.y + box.minY + 3, width: foldPlaceholderWidth - 6, height: max(8, box.height - 6))
            NSColor.secondaryLabelColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            let font = textStorage?.attribute(.font, at: fold.location, effectiveRange: nil) as? NSFont ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
            let mark = NSAttributedString(string: "⋯", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
            let size = mark.size()
            mark.draw(at: NSPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2))
        }
    }

    // MARK: Invisibles

    var showsInvisibles = false {
        didSet {
            guard showsInvisibles != oldValue, let length = textStorage?.length else { return }
            invalidateDisplay(forCharacterRange: NSRange(location: 0, length: length))
        }
    }

    private struct SymbolKey: Hashable {
        var symbol: Character
        var fontName: String
        var size: CGFloat
    }

    private var symbols: [SymbolKey: NSAttributedString] = [:]

    /// Invisible and look-alike characters (zero-width, bidi controls, unusual spaces…) are always marked in
    /// orange, whatever `showsInvisibles` says: they're how "looks right, behaves wrong" edits happen.
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, glyphsToShow.length > 0 else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let risky = RiskyCharacters.scan(storage.string as NSString, in: characters)
        guard !risky.isEmpty else { return }
        for item in risky {
            let glyphs = glyphRange(forCharacterRange: item.range, actualCharacterRange: nil)
            guard glyphs.length > 0, let container = textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) else { continue }
            var rect = boundingRect(forGlyphRange: glyphs, in: container)
            if rect.width < 4 {
                // Zero-width characters get a visible bar where they sit.
                rect.origin.x -= (4 - rect.width) / 2
                rect.size.width = 4
            }
            rect = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: 0, dy: 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            NSColor.systemOrange.withAlphaComponent(0.35).setFill()
            path.fill()
            NSColor.systemOrange.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawFoldPlaceholders(forGlyphRange: glyphsToShow, at: origin)
        guard showsInvisibles, let storage = textStorage, glyphsToShow.length > 0 else { return }
        let text = storage.string as NSString
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for index in characters.location..<NSMaxRange(characters) {
            let symbol: Character
            switch text.character(at: index) {
            case 0x20: symbol = "·"
            case 0x09: symbol = "→"
            case 0x0A:
                if index > 0 && text.character(at: index - 1) == 0x0D { continue }  // \r\n is one break, marked at \r
                symbol = "¬"
            case 0x0D: symbol = index + 1 < text.length && text.character(at: index + 1) == 0x0A ? "↵" : "←"
            case 0x2028, 0x2029: symbol = "¶"
            default: continue
            }
            let glyph = glyphIndexForCharacter(at: index)
            guard isValidGlyphIndex(glyph) else { continue }
            let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
            let location = location(forGlyphAt: glyph)
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
            let mark = attributedSymbol(symbol, font: font)
            var x = origin.x + fragment.minX + location.x
            if symbol == "·", let container = textContainer(forGlyphAt: glyph, effectiveRange: nil) {
                // Centre the dot over the space's advance.
                let advance = boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).width
                x += max(0, (advance - mark.size().width) / 2)
            }
            mark.draw(at: NSPoint(x: x, y: origin.y + fragment.minY + location.y - font.ascender))
        }
    }

    private func attributedSymbol(_ symbol: Character, font: NSFont) -> NSAttributedString {
        let key = SymbolKey(symbol: symbol, fontName: font.fontName, size: font.pointSize)
        if let cached = symbols[key] { return cached }
        let mark = NSAttributedString(string: String(symbol), attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor])
        symbols[key] = mark
        return mark
    }
}
