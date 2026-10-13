import AppKit

/// The line-number gutter: a vertical ruler that numbers logical lines (a wrapped line gets one number) and
/// highlights the caret's line. It stays put when the text scrolls horizontally.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: EditorTextView?
    private let lineIndex: LineIndex
    private var digits = 0

    init(textView: EditorTextView, scrollView: NSScrollView, lineIndex: LineIndex) {
        self.textView = textView
        self.lineIndex = lineIndex
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        // Since macOS 14 views don't clip by default; the ruler must not paint over the text.
        clipsToBounds = true
        updateThickness()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// A faint hairline between the numbers and the text, softer still in dark mode.
    private static let separatorColor = NSColor(name: "gutterSeparator") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.07)
            : NSColor(white: 0, alpha: 0.09)
    }

    /// Draws only the numbers and our hairline: NSRulerView's own drawing adds a heavier border.
    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    private var numberFont: NSFont {
        let size = textView?.font?.pointSize ?? 13
        return .monospacedDigitSystemFont(ofSize: max(9, (size * 0.85).rounded()), weight: .regular)
    }

    /// Call after edits and font changes; widens the gutter when the line count gains a digit.
    func textDidChange() {
        updateThickness()
        needsDisplay = true
    }

    private func updateThickness() {
        guard let textView else { return }
        let count = lineIndex.lineCount(in: textView.string as NSString)
        let newDigits = max(3, String(count).count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: numberFont]).width
        let thickness = (CGFloat(newDigits) * digitWidth + 22).rounded()
        if newDigits != digits || abs(ruleThickness - thickness) > 0.5 {
            digits = newDigits
            ruleThickness = thickness
        }
    }

    override func drawHashMarksAndLabels(in dirtyRect: NSRect) {
        let rect = dirtyRect.intersection(bounds)
        NSColor.textBackgroundColor.setFill()
        rect.fill()
        Self.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let text = textView.string as NSString
        let starts = lineIndex.lineStarts(in: text)
        let currentLine = lineIndex.line(of: textView.selectedRange().location, in: text)
        let font = numberFont
        let yOffset = convert(NSPoint.zero, from: textView).y + textView.textContainerOrigin.y
        let right = ruleThickness - 10

        func drawNumber(_ line: Int, baseline: CGFloat) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: line == currentLine ? NSColor.labelColor : NSColor.tertiaryLabelColor,
            ]
            let label = String(line + 1) as NSString
            let width = label.size(withAttributes: attributes).width
            label.draw(at: NSPoint(x: right - width, y: baseline - font.ascender), withAttributes: attributes)
        }

        let visible = textView.visibleRect
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, range, _ in
            let character = layoutManager.characterIndexForGlyph(at: range.location)
            let line = self.lineIndex.line(of: character, in: text)
            guard starts[line] == character else { return }  // the continuation of a wrapped line
            drawNumber(line, baseline: yOffset + fragment.minY + layoutManager.location(forGlyphAt: range.location).y)
        }
        // The empty line after a final line break has no glyphs.
        if layoutManager.extraLineFragmentTextContainer != nil {
            let extra = layoutManager.extraLineFragmentRect
            drawNumber(starts.count - 1, baseline: yOffset + extra.minY + (textView.font?.ascender ?? font.ascender))
        }
    }
}
