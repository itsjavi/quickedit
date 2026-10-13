import AppKit
import QuickEditCore

/// The code editor's text view: indentation-aware Tab/Return, the document's own line endings for new lines,
/// and a current-line highlight. Line commands live in extensions.
final class EditorTextView: NSTextView {
    var indentation = Indentation(style: .spaces, width: 4)
    /// What Return inserts, so a CRLF file stays CRLF.
    var lineEnding = LineEnding.lf
    /// The language's comment markers, for Toggle Comment.
    var commentStyle = CommentStyle.none
    var highlightsCurrentLine = true {
        didSet { if highlightsCurrentLine != oldValue { needsDisplay = true } }
    }

    static let currentLineColor = NSColor(name: "currentLine") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.055)
            : NSColor(white: 0, alpha: 0.045)
    }

    // MARK: Typing

    override func insertNewline(_ sender: Any?) {
        guard selectedRanges.count == 1, let range = selectedRanges.first?.rangeValue else {
            super.insertNewline(sender)
            return
        }
        // Keep the current line's indentation.
        let text = string as NSString
        let lineStart = text.lineRange(for: NSRange(location: range.location, length: 0)).location
        let before = text.substring(with: NSRange(location: lineStart, length: range.location - lineStart))
        let indent = before.prefix { $0 == " " || $0 == "\t" }
        insertText(lineEnding.rawValue + indent, replacementRange: range)
    }

    override func insertTab(_ sender: Any?) {
        let selection = selectedRange()
        let text = string as NSString
        if selection.length > 0, text.substring(with: selection).contains(where: \.isNewline) {
            indentSelectedLines(nil)
            return
        }
        if indentation.style == .tabs {
            insertText("\t", replacementRange: selection)
            return
        }
        // Spaces up to the next indent stop, counting tabs at their display width.
        let lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let before = text.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
        let width = max(indentation.width, 1)
        let column = before.reduce(0) { column, character in character == "\t" ? column + width - column % width : column + 1 }
        insertText(String(repeating: " ", count: width - column % width), replacementRange: selection)
    }

    override func insertBacktab(_ sender: Any?) {
        outdentSelectedLines(nil)
    }

    @objc func indentSelectedLines(_ sender: Any?) {
        let unit = indentation.unit
        transformSelectedLines { $0.isEmpty ? $0 : unit + $0 }
    }

    @objc func outdentSelectedLines(_ sender: Any?) {
        let width = max(indentation.width, 1)
        transformSelectedLines { line in
            if line.first == "\t" { return String(line.dropFirst()) }
            let spaces = line.prefix { $0 == " " }.count
            return String(line.dropFirst(min(spaces, width)))
        }
    }

    /// Pasted line breaks become the document's own, so a paste never mixes line endings into the file.
    override func paste(_ sender: Any?) {
        guard isEditable, let pasted = NSPasteboard.general.string(forType: .string),
              pasted.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
        else {
            super.paste(sender)
            return
        }
        insertText(LineEndings.convert(pasted, to: lineEnding), replacementRange: selectedRange())
    }

    // MARK: Line editing helpers

    /// The lines touched by `range` as (content range, full range including the line ending) pairs.
    func lines(in range: NSRange) -> [(content: NSRange, full: NSRange)] {
        let text = string as NSString
        let lineRange = text.lineRange(for: range)
        var result: [(NSRange, NSRange)] = []
        var index = lineRange.location
        repeat {
            var start = 0
            var end = 0
            var contentsEnd = 0
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
            result.append((NSRange(location: start, length: contentsEnd - start), NSRange(location: start, length: end - start)))
            index = end
        } while index < NSMaxRange(lineRange)
        return result
    }

    /// Rewrites the content of every line touched by the selection (line endings untouched) as one undoable change.
    func transformSelectedLines(_ transform: (String) -> String) {
        let text = string as NSString
        let selection = selectedRange()
        let affected = lines(in: selection)
        guard let first = affected.first, let last = affected.last else { return }
        let whole = NSRange(location: first.full.location, length: NSMaxRange(last.content) - first.full.location)
        var replacement = ""
        for (offset, line) in affected.enumerated() {
            replacement += transform(text.substring(with: line.content))
            if offset < affected.count - 1 {
                replacement += text.substring(with: NSRange(location: NSMaxRange(line.content), length: NSMaxRange(line.full) - NSMaxRange(line.content)))
            }
        }
        guard replacement != text.substring(with: whole) else { return }
        replace(whole, with: replacement)
        let newLength = (replacement as NSString).length
        if selection.length == 0 && affected.count == 1 {
            let shift = newLength - whole.length
            setSelectedRange(NSRange(location: max(whole.location, selection.location + shift), length: 0))
        } else {
            setSelectedRange(NSRange(location: whole.location, length: newLength))
        }
    }

    /// Replaces `range` as one undoable edit that keeps the scroll position.
    func replace(_ range: NSRange, with replacement: String) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
    }

    // MARK: Current line

    private var highlightedLineRect: NSRect?

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard highlightsCurrentLine else { return }
        let newRect = currentLineRect()
        if newRect != highlightedLineRect {
            if let old = highlightedLineRect { setNeedsDisplay(old, avoidAdditionalLayout: true) }
            if let newRect { setNeedsDisplay(newRect, avoidAdditionalLayout: true) }
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard highlightsCurrentLine else {
            highlightedLineRect = nil
            return
        }
        highlightedLineRect = currentLineRect()
        guard let line = highlightedLineRect, line.intersects(rect) else { return }
        Self.currentLineColor.setFill()
        line.intersection(rect).fill()
    }

    /// The full-width rect of the caret's logical line (all its wrapped fragments); nil with a selection.
    func currentLineRect() -> NSRect? {
        guard let layoutManager, let container = textContainer, selectedRanges.count == 1 else { return nil }
        let selection = selectedRange()
        guard selection.length == 0 else { return nil }
        let text = string as NSString
        let origin = textContainerOrigin
        if selection.location >= text.length,
           text.length == 0 || [0x0A, 0x0D].contains(text.character(at: text.length - 1)) {
            // The empty last line after a final line break.
            guard layoutManager.extraLineFragmentTextContainer != nil else { return nil }
            let extra = layoutManager.extraLineFragmentRect
            return NSRect(x: 0, y: extra.minY + origin.y, width: bounds.width, height: extra.height)
        }
        let paragraph = text.paragraphRange(for: NSRange(location: min(selection.location, text.length), length: 0))
        var glyphs = layoutManager.glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
        if glyphs.length > 10_000 {
            // A long logical line (a minified file) is measured only where it's on screen: all of it would mean
            // laying out megabytes of wrapped text on every keystroke.
            let visible = layoutManager.glyphRange(
                forBoundingRectWithoutAdditionalLayout: visibleRect.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
            glyphs = NSIntersectionRange(glyphs, visible)
        }
        guard glyphs.length > 0 else { return nil }
        var union = NSRect.null
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, fragmentContainer, _, _ in
            if fragmentContainer === container { union = union.union(rect) }
        }
        guard !union.isNull else { return nil }
        return NSRect(x: 0, y: union.minY + origin.y, width: bounds.width, height: union.height)
    }
}
