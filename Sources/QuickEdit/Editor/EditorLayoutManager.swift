import AppKit
import QuickEditCore

/// TextKit 1 layout manager for the editor. With `showsInvisibles` it draws spaces as ·, tabs as →, and line endings
/// by kind (LF ¬, CRLF ↵, CR ←) in a faint colour over the text, without changing the text or its layout.
/// (NSLayoutManager's own `showsInvisibleCharacters` glyphs look poor and can't be styled.)
nonisolated final class EditorLayoutManager: NSLayoutManager {
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
