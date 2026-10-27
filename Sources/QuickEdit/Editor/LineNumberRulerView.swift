import AppKit
import QuickEditCore

/// The line-number gutter: a vertical ruler that numbers logical lines (a wrapped line gets one number) and
/// highlights the caret's line. It stays put when the text scrolls horizontally.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: EditorTextView?
    private let lineIndex: LineIndex
    private var digits = 0
    /// Supplies fold markers and toggles folds (the window's editor).
    weak var editor: EditorViewController?
    /// Width of the fold-arrow column at the gutter's right edge.
    private static let foldColumn: CGFloat = 14

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
        let thickness = (CGFloat(newDigits) * digitWidth + 22 + Self.foldColumn).rounded()
        if newDigits != digits || abs(ruleThickness - thickness) > 0.5 {
            digits = newDigits
            ruleThickness = thickness
        }
    }

    private func drawFoldArrow(folded: Bool, baseline: CGFloat, font: NSFont) {
        let size: CGFloat = 7
        let centerX = ruleThickness - Self.foldColumn / 2 - 4
        let centerY = baseline - font.xHeight / 2
        let path = NSBezierPath()
        if folded {
            path.move(to: NSPoint(x: centerX - size / 3, y: centerY - size / 2))
            path.line(to: NSPoint(x: centerX + size / 2, y: centerY))
            path.line(to: NSPoint(x: centerX - size / 3, y: centerY + size / 2))
        } else {
            path.move(to: NSPoint(x: centerX - size / 2, y: centerY - size / 3))
            path.line(to: NSPoint(x: centerX + size / 2, y: centerY - size / 3))
            path.line(to: NSPoint(x: centerX, y: centerY + size / 2))
        }
        path.close()
        (folded ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setFill()
        path.fill()
    }

    /// A click in the fold column toggles the fold that starts on that line.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard point.x >= ruleThickness - Self.foldColumn - 6, let editor, let textView,
              let layoutManager = textView.layoutManager, let container = textView.textContainer
        else { return super.mouseDown(with: event) }
        let inText = textView.convert(point, from: self)
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: inText.y - textView.textContainerOrigin.y), in: container)
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        let line = lineIndex.line(of: character, in: textView.string as NSString)
        let text = textView.string as NSString
        let lineStart = lineIndex.start(ofLine: line, in: text)
        let isLastLine = line + 1 >= lineIndex.lineCount(in: text)
        let lineEnd = isLastLine ? text.length : lineIndex.start(ofLine: line + 1, in: text)
        let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
        if editor.foldMarkers(in: lineRange)[line] != nil { editor.toggleFold(atLine: line) } else { super.mouseDown(with: event) }
    }

    /// Typeset numbers by label, drawn in whatever colour is set: typesetting each one on every scrolled frame was
    /// most of the time a fast scroll spent on the main thread.
    private var labels: [Int: (line: CTLine, width: CGFloat)] = [:]
    private var labelsFont: NSFont?

    private func label(_ number: Int, font: NSFont) -> (line: CTLine, width: CGFloat) {
        if labelsFont != font || labels.count > 5_000 {
            labels.removeAll()
            labelsFont = font
        }
        if let cached = labels[number] { return cached }
        let string = NSAttributedString(string: String(number), attributes: [
            .font: font, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
        let line = CTLineCreateWithAttributedString(string)
        let label = (line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        labels[number] = label
        return label
    }

    override func drawHashMarksAndLabels(in dirtyRect: NSRect) {
        let rect = dirtyRect.intersection(bounds)
        NSColor.textBackgroundColor.setFill()
        rect.fill()
        Self.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let text = textView.string as NSString
        let starts = lineIndex.lineStarts(in: text)
        let currentLine = lineIndex.line(of: textView.selectedRange().location, in: text)
        let font = numberFont
        let yOffset = convert(NSPoint.zero, from: textView).y + textView.textContainerOrigin.y
        let right = ruleThickness - 10 - Self.foldColumn
        // The lines beside the dirty rect, which AppKit may ask for ahead of a scroll, not just the visible ones.
        let textRect = textView.convert(rect, from: self)
        let glyphs = layoutManager.glyphRange(
            forBoundingRect: NSRect(x: 0, y: textRect.minY - textView.textContainerOrigin.y, width: textView.bounds.width, height: textRect.height),
            in: container)
        // Only these lines' markers (each redraw after an edit would otherwise walk a large file's whole tree), up to
        // the end of the last line, where its region's hidden range starts.
        let shownText = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let lastLine = lineIndex.line(of: shownText.upperBound, in: text)
        let lastLineEnd = lastLine + 1 < starts.count ? starts[lastLine + 1] : text.length
        let markerRange = NSRange(
            location: shownText.location, length: min(lastLineEnd, shownText.upperBound + 10_000) - shownText.location)
        let markers = editor?.foldMarkers(in: markerRange) ?? [:]
        // The view is flipped: CoreText draws upright with a flipped text matrix, at the baseline.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        func drawNumber(_ line: Int, baseline: CGFloat) {
            (line == currentLine ? NSColor.labelColor : NSColor.tertiaryLabelColor).setFill()
            let label = label(line + 1, font: font)
            context.textPosition = CGPoint(x: right - label.width, y: baseline)
            CTLineDraw(label.line, context)
            if let isFolded = markers[line] {
                drawFoldArrow(folded: isFolded, baseline: baseline, font: font)
            }
        }

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
