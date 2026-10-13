import Foundation

/// Table edits as minimal text edits: only the bytes of the touched cells, rows or delimiters change. Every edit's
/// range refers to the text this `DelimitedText` was parsed from; multi-edit results are sorted from the end of the
/// text to the start, so applying them in order keeps the remaining ranges valid.
extension DelimitedText {
    /// Sets one cell. Quoted fields stay quoted; others get quotes only when the value needs them (delimiter, quote,
    /// CR or LF, or leading/trailing space or tab). Line breaks inside the value become `lineEnding`. Short rows are
    /// padded with delimiters, unless the value is empty (a missing cell already reads as empty). `row ==
    /// rows.count` appends a new row.
    public func editCell(row: Int, column: Int, value: String, lineEnding: LineEnding) -> TextEdit {
        precondition(row >= 0 && row <= rows.count && column >= 0, "Cell out of range")
        if row == rows.count {
            let field = encodeField(value, quoted: false, lineEnding: lineEnding)
            return appendRow(String(repeating: delimiter, count: column) + field, lineEnding: lineEnding)
        }
        let target = rows[row]
        if column < target.cells.count {
            let cell = target.cells[column]
            var field = encodeField(value, quoted: cell.isQuoted, lineEnding: lineEnding)
            // Emptying the only cell of a last line without a line break would drop the row: keep it as `""`.
            if field.isEmpty, target.cells.count == 1, isUnterminatedLastRow(row) { field = "\"\"" }
            return TextEdit(range: cell.range, replacement: field)
        }
        let end = NSRange(location: target.range.upperBound, length: 0)
        if value.isEmpty { return TextEdit(range: end, replacement: "") }
        let padding = String(repeating: delimiter, count: column - target.cells.count + 1)
        return TextEdit(range: end, replacement: padding + encodeField(value, quoted: false, lineEnding: lineEnding))
    }

    /// Inserts an empty row (`columnCount - 1` delimiters) before row `index`, or after the last row when `index ==
    /// rows.count`. Appending keeps the file's final-newline state: after a last row without a line break, the
    /// break goes before the new row instead.
    public func insertRow(at index: Int, lineEnding: LineEnding) -> TextEdit {
        precondition(index >= 0 && index <= rows.count, "Row out of range")
        let content = String(repeating: delimiter, count: max(columnCount - 1, 0))
        if index < rows.count {
            return TextEdit(range: NSRange(location: rows[index].range.location, length: 0), replacement: content + lineEnding.rawValue)
        }
        return appendRow(content, lineEnding: lineEnding)
    }

    /// Deletes rows with their line endings, one edit per run of adjacent rows, last first. Deleting the last row of
    /// a file without a final newline removes the line break before it instead, so the file still doesn't end with
    /// one. Indices out of range are ignored.
    public func deleteRows(_ indices: IndexSet) -> [TextEdit] {
        let valid = indices.filteredIndexSet { rows.indices.contains($0) }
        var edits: [TextEdit] = []
        for run in valid.rangeView.reversed() {
            let first = run.lowerBound, last = run.upperBound - 1
            var start = rows[first].range.location
            let end = rows[last].lineEnding.upperBound
            if isUnterminatedLastRow(last), first > 0 {
                start = rows[first - 1].lineEnding.location
            }
            edits.append(TextEdit(range: NSRange(location: start, length: end - start), replacement: ""))
        }
        return edits
    }

    /// Inserts an empty column before column `index` (or appends one when `index == columnCount`), one edit per row
    /// that needs it, last row first. Short rows that don't reach `index` and blank lines are left alone: their
    /// missing cells already read as empty.
    public func insertColumn(at index: Int) -> [TextEdit] {
        precondition(index >= 0 && index <= columnCount, "Column out of range")
        var edits: [TextEdit] = []
        for row in rows.reversed() where !row.isBlank {
            if index < row.cells.count {
                edits.append(TextEdit(range: NSRange(location: row.cells[index].range.location, length: 0), replacement: String(delimiter)))
            } else if index == row.cells.count, index == columnCount {
                edits.append(TextEdit(range: NSRange(location: row.range.upperBound, length: 0), replacement: String(delimiter)))
            }
        }
        return edits
    }

    /// Deletes column `index` with one adjacent delimiter in every row that has it, last row first. A row whose only
    /// cell is deleted becomes an empty line.
    public func deleteColumn(_ index: Int) -> [TextEdit] {
        precondition(index >= 0, "Column out of range")
        var edits: [TextEdit] = []
        for row in rows.reversed() where index < row.cells.count && !row.isBlank {
            let cells = row.cells
            let range: NSRange
            if cells.count == 1 {
                range = cells[0].range
            } else if index < cells.count - 1 {
                range = NSRange(location: cells[index].range.location, length: cells[index + 1].range.location - cells[index].range.location)
            } else {
                let start = cells[index - 1].range.upperBound
                range = NSRange(location: start, length: cells[index].range.upperBound - start)
            }
            edits.append(TextEdit(range: range, replacement: ""))
        }
        return edits
    }

    // MARK: - Helpers

    /// The field text for `value`: quoted when `quoted` or when the value needs it, with quotes doubled.
    func encodeField(_ value: String, quoted: Bool, lineEnding: LineEnding) -> String {
        var value = value
        let delimiterUnit = delimiter.utf16.first!
        var hasBreak = false
        var needsQuotes = quoted
        for unit in value.utf16 {
            switch unit {
            case 0x0A, 0x0D:
                hasBreak = true
                needsQuotes = true
            case 0x22, delimiterUnit:
                needsQuotes = true
            default: break
            }
        }
        if hasBreak { value = LineEndings.convert(value, to: lineEnding) }
        if let first = value.unicodeScalars.first, let last = value.unicodeScalars.last,
           first == " " || first == "\t" || last == " " || last == "\t" {
            needsQuotes = true
        }
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// The last row has no line ending (the file doesn't end with a newline).
    func isUnterminatedLastRow(_ index: Int) -> Bool {
        index == rows.count - 1 && rows[index].lineEnding.length == 0
    }

    /// Appends a row with `content` while keeping the final-newline state. Empty content after an unterminated last
    /// row would leave no visible row, so it becomes `""` there.
    private func appendRow(_ content: String, lineEnding: LineEnding) -> TextEdit {
        guard let last = rows.last else {
            return TextEdit(range: NSRange(location: 0, length: 0), replacement: content + lineEnding.rawValue)
        }
        let end = NSRange(location: last.lineEnding.upperBound, length: 0)
        if last.lineEnding.length > 0 { return TextEdit(range: end, replacement: content + lineEnding.rawValue) }
        return TextEdit(range: end, replacement: lineEnding.rawValue + (content.isEmpty ? "\"\"" : content))
    }
}
