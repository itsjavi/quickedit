import Foundation

/// CSV/TSV text parsed into rows and cells with exact UTF-16 ranges, so a table view can edit cells by replacing only
/// their bytes. Parsing follows RFC 4180 leniently: `""` escapes a quote inside a quoted field, quoted fields may hold
/// delimiters and line breaks, rows end with LF, CRLF or CR, rows may have different lengths, and the last row may or
/// may not end with a line break. Rows cover the whole text, so nothing is lost or reinterpreted.
public struct DelimitedText: Sendable {
    public struct Cell: Equatable, Sendable {
        /// The whole field, quotes included.
        public let range: NSRange
        /// The field's value: quotes removed and `""` unescaped for quoted fields, the raw text otherwise.
        public let value: String
        /// The field starts with a quote. Edits keep the quotes of quoted fields.
        public let isQuoted: Bool

        public init(range: NSRange, value: String, isQuoted: Bool) {
            self.range = range
            self.value = value
            self.isQuoted = isQuoted
        }
    }

    public struct Row: Equatable, Sendable {
        /// At least one cell: an empty line is a row with one empty cell.
        public let cells: [Cell]
        /// The row's text without its line ending (multi-line quoted cells included).
        public let range: NSRange
        /// The row's line ending: length 2 for CRLF, 1 for LF or CR, 0 for a last row without one.
        public let lineEnding: NSRange

        public init(cells: [Cell], range: NSRange, lineEnding: NSRange) {
            self.cells = cells
            self.range = range
            self.lineEnding = lineEnding
        }

        /// An empty line: a single empty, unquoted cell.
        public var isBlank: Bool { range.length == 0 }
    }

    /// `,`, `\t`, `;` or `|` (any single UTF-16 character works).
    public let delimiter: Character
    public let rows: [Row]
    /// The most cells in any row.
    public let columnCount: Int

    public init(delimiter: Character, rows: [Row]) {
        self.delimiter = delimiter
        self.rows = rows
        self.columnCount = rows.reduce(0) { max($0, $1.cells.count) }
    }

    /// The value at a row and column; missing cells of short rows read as empty.
    public func value(row: Int, column: Int) -> String {
        guard rows.indices.contains(row), rows[row].cells.indices.contains(column) else { return "" }
        return rows[row].cells[column].value
    }

    // MARK: - Delimiter detection

    static let candidates: [Character] = [",", "\t", ";", "|"]

    /// `.tsv` and `.tab` files are tab-separated. Otherwise the candidate (`,` `\t` `;` `|`, outside quotes) that
    /// appears the same number of times on the most lines of the first 50 wins, preferring more occurrences, then
    /// the order above; `,` when none appears.
    public static func detectDelimiter(_ text: NSString, fileExtension: String?) -> Character {
        if let ext = fileExtension?.lowercased(), ext == "tsv" || ext == "tab" { return "\t" }
        let units = candidates.map { $0.utf16.first! }
        var lines: [[Int]] = []
        var counts = [Int](repeating: 0, count: units.count)
        var inQuotes = false
        var lineHasContent = false
        let limit = min(text.length, 65_536)
        var index = 0
        while index < limit, lines.count < 50 {
            let unit = text.character(at: index)
            index += 1
            if unit == 0x22 {
                inQuotes.toggle()
            } else if !inQuotes, unit == 0x0A || unit == 0x0D {
                if unit == 0x0D, index < limit, text.character(at: index) == 0x0A { index += 1 }
                if lineHasContent { lines.append(counts) }
                counts = [Int](repeating: 0, count: units.count)
                lineHasContent = false
                continue
            } else if !inQuotes, let candidate = units.firstIndex(of: unit) {
                counts[candidate] += 1
            }
            lineHasContent = true
        }
        // A last line cut by the sample limit is incomplete; use it only when it's all there is.
        if lineHasContent, index == text.length || lines.isEmpty { lines.append(counts) }

        var best: (candidate: Int, lines: Int, count: Int)?
        for candidate in units.indices {
            var frequency: [Int: Int] = [:]
            for line in lines where line[candidate] > 0 { frequency[line[candidate], default: 0] += 1 }
            guard let (count, lineCount) = frequency.max(by: { ($0.value, $0.key) < ($1.value, $1.key) }) else { continue }
            if let current = best, (current.lines, current.count) >= (lineCount, count) { continue }
            best = (candidate, lineCount, count)
        }
        return best.map { candidates[$0.candidate] } ?? ","
    }

    // MARK: - Parsing

    /// Parses `text`. `delimiter` must be a single UTF-16 character.
    public static func parse(_ text: NSString, delimiter: Character) -> DelimitedText {
        precondition(delimiter.utf16.count == 1, "The delimiter must be a single UTF-16 character")
        let length = text.length
        guard length > 0 else { return DelimitedText(delimiter: delimiter, rows: []) }
        if let pointer = CFStringGetCharactersPtr(text as CFString) {
            let units = UnsafeBufferPointer(start: pointer, count: length)
            return DelimitedText(delimiter: delimiter, rows: parseRows(units, delimiter: delimiter.utf16.first!))
        }
        var buffer = [UInt16](repeating: 0, count: length)
        return buffer.withUnsafeMutableBufferPointer { units in
            text.getCharacters(units.baseAddress!, range: NSRange(location: 0, length: length))
            return DelimitedText(delimiter: delimiter, rows: parseRows(UnsafeBufferPointer(units), delimiter: delimiter.utf16.first!))
        }
    }

    private static func parseRows(_ units: UnsafeBufferPointer<UInt16>, delimiter: UInt16) -> [Row] {
        let quote: UInt16 = 0x22, cr: UInt16 = 0x0D, lf: UInt16 = 0x0A
        let length = units.count
        func string(_ range: Range<Int>) -> String {
            String(decoding: UnsafeBufferPointer(rebasing: units[range]), as: UTF16.self)
        }
        func endOfField(from start: Int) -> Int {
            var index = start
            while index < length {
                let unit = units[index]
                if unit == delimiter || unit == lf || unit == cr { break }
                index += 1
            }
            return index
        }

        var rows: [Row] = []
        var index = 0
        while index < length {
            let rowStart = index
            var cells: [Cell] = []
            cells.reserveCapacity(rows.last?.cells.count ?? 8)
            while true {
                let fieldStart = index
                if index < length, units[index] == quote {
                    index += 1
                    let contentStart = index
                    var hasEscapes = false
                    var closed = false
                    while index < length {
                        if units[index] == quote {
                            if index + 1 < length, units[index + 1] == quote {
                                hasEscapes = true
                                index += 2
                                continue
                            }
                            closed = true
                            break
                        }
                        index += 1
                    }
                    let contentEnd = index
                    if closed { index += 1 }
                    // Leniency: text after the closing quote (`"a"b`) belongs to the value.
                    let trailingStart = index
                    index = endOfField(from: index)
                    var value: String
                    if hasEscapes {
                        var unescaped = [UInt16]()
                        unescaped.reserveCapacity(contentEnd - contentStart)
                        var cursor = contentStart
                        while cursor < contentEnd {
                            unescaped.append(units[cursor])
                            cursor += units[cursor] == quote ? 2 : 1
                        }
                        value = String(decoding: unescaped, as: UTF16.self)
                    } else {
                        value = string(contentStart..<contentEnd)
                    }
                    if trailingStart < index { value += string(trailingStart..<index) }
                    cells.append(Cell(range: NSRange(location: fieldStart, length: index - fieldStart), value: value, isQuoted: true))
                } else {
                    index = endOfField(from: index)
                    cells.append(Cell(
                        range: NSRange(location: fieldStart, length: index - fieldStart),
                        value: string(fieldStart..<index), isQuoted: false))
                }
                guard index < length, units[index] == delimiter else { break }
                index += 1
            }
            let rowEnd = index
            var lineEndingLength = 0
            if index < length {
                if units[index] == cr {
                    lineEndingLength = index + 1 < length && units[index + 1] == lf ? 2 : 1
                } else if units[index] == lf {
                    lineEndingLength = 1
                }
            }
            index += lineEndingLength
            rows.append(Row(
                cells: cells, range: NSRange(location: rowStart, length: rowEnd - rowStart),
                lineEnding: NSRange(location: rowEnd, length: lineEndingLength)))
        }
        return rows
    }
}
