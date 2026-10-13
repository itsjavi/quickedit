import Foundation

/// Rainbow columns for CSV/TSV: each field becomes a `.column(index)` token. Double-quoted fields may contain the
/// delimiter, `""` escapes and newlines. Scanning starts at the first visible line, which is assumed not to begin
/// inside a quoted field.
final class DelimitedEngine: HighlightEngine {
    private let delimiter: UInt16
    private var text: NSString = ""
    private var lines = LineIndex()

    init(delimiter: UInt16) {
        self.delimiter = delimiter
    }

    func setText(_ text: NSString) {
        self.text = text
        lines = LineIndex(text: text)
    }

    func applyEdit(replacing oldRange: NSRange, with replacementLength: Int, in newText: NSString) -> [NSRange] {
        let edited = NSRange(location: oldRange.location, length: replacementLength)
        // A quote can open or close a multi-line field, which renumbers the columns of every following line. The
        // caller may pass the same mutable string again, so the deleted text is only checked when it's still there.
        let quote = "\""
        let deletedQuote =
            oldRange.length > 0
            && (text === newText || oldRange.upperBound > text.length
                || text.range(of: quote, options: .literal, range: oldRange).location != NSNotFound)
        let togglesQuotes =
            deletedQuote || newText.range(of: quote, options: .literal, range: edited).location != NSNotFound
        lines.applyEdit(oldRange: oldRange, replacementLength: replacementLength, newText: newText)
        text = newText
        let lineRange = lines.lineRange(covering: edited, length: newText.length)
        if togglesQuotes {
            return [NSRange(location: lineRange.location, length: newText.length - lineRange.location)]
        }
        return [lineRange]
    }

    func tokens(in range: NSRange) -> [SyntaxToken] {
        let length = text.length
        guard let range = range.clipped(to: NSRange(location: 0, length: length)) else { return [] }
        let scan = lines.lineRange(covering: range, length: length)

        var tokens: [SyntaxToken] = []
        var column = 0
        var fieldStart = scan.location
        var inQuotes = false

        func endField(at end: Int) {
            if end > fieldStart, let clipped = NSRange(location: fieldStart, length: end - fieldStart).clipped(to: range) {
                tokens.append(SyntaxToken(range: clipped, kind: .column(column)))
            }
        }

        TextChunks.forEachChunk(of: text, in: scan) { buffer, location in
            for (index, unit) in buffer.enumerated() {
                let offset = location + index
                if unit == 0x22 {  // "
                    inQuotes.toggle()
                } else if inQuotes {
                    continue
                } else if unit == delimiter {
                    endField(at: offset)
                    column += 1
                    fieldStart = offset + 1
                } else if unit == 0x0A || unit == 0x0D {
                    endField(at: offset)
                    column = 0
                    fieldStart = offset + 1
                }
            }
        }
        endField(at: scan.upperBound)
        return tokens
    }
}
