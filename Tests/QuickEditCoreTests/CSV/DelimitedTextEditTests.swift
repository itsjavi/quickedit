import Foundation
import QuickEditCore
import Testing

/// Applies edits in order, as the app does, and returns the new text.
private func applying(_ edits: [TextEdit], to text: String) -> String {
    let mutable = NSMutableString(string: text)
    for edit in edits { edit.apply(to: mutable) }
    return mutable as String
}

private func parse(_ text: String, _ delimiter: Character = ",") -> DelimitedText {
    DelimitedText.parse(text as NSString, delimiter: delimiter)
}

/// Checks that `result` differs from `original` only inside `range` (UTF-16, in the original): everything before and
/// after it is identical.
private func expectChangedOnlyInside(
    _ range: NSRange, original: String, result: String, sourceLocation: SourceLocation = #_sourceLocation
) {
    let before = Array(original.utf16), after = Array(result.utf16)
    #expect(Array(after.prefix(range.location)) == Array(before.prefix(range.location)), sourceLocation: sourceLocation)
    let suffixLength = before.count - range.upperBound
    #expect(after.count >= range.location + suffixLength, sourceLocation: sourceLocation)
    #expect(Array(after.suffix(suffixLength)) == Array(before.suffix(suffixLength)), sourceLocation: sourceLocation)
}

/// Multi-edit results must run from the end of the text to the start without overlapping.
private func expectDescending(_ edits: [TextEdit], sourceLocation: SourceLocation = #_sourceLocation) {
    for (later, earlier) in zip(edits, edits.dropFirst()) {
        #expect(earlier.range.upperBound <= later.range.location, sourceLocation: sourceLocation)
    }
}

@Suite struct EditCellTests {
    @Test func replacesOnlyTheCell() {
        let text = "a,b,c\r\n1,2,3\r\n4,5,6\r\n"
        let table = parse(text)
        let edit = table.editCell(row: 1, column: 1, value: "two", lineEnding: .crlf)
        #expect(edit == TextEdit(range: table.rows[1].cells[1].range, replacement: "two"))
        let result = applying([edit], to: text)
        #expect(result == "a,b,c\r\n1,two,3\r\n4,5,6\r\n")
        expectChangedOnlyInside(table.rows[1].cells[1].range, original: text, result: result)
        #expect(parse(result).value(row: 1, column: 1) == "two")
    }

    @Test func keepsQuotesOfQuotedFields() {
        let text = "\"x\",\"y\",z\n"
        let table = parse(text)
        #expect(applying([table.editCell(row: 0, column: 1, value: "new", lineEnding: .lf)], to: text) == "\"x\",\"new\",z\n")
        #expect(applying([table.editCell(row: 0, column: 1, value: "", lineEnding: .lf)], to: text) == "\"x\",\"\",z\n")
        #expect(applying([table.editCell(row: 0, column: 2, value: "w", lineEnding: .lf)], to: text) == "\"x\",\"y\",w\n")
    }

    @Test(arguments: [
        ("a,b", "\"a,b\"", "a,b"),
        ("say \"hi\"", "\"say \"\"hi\"\"\"", "say \"hi\""),
        ("two\nlines", "\"two\r\nlines\"", "two\r\nlines"),
        ("cr\ronly", "\"cr\r\nonly\"", "cr\r\nonly"),
        (" lead", "\" lead\"", " lead"),
        ("trail\t", "\"trail\t\"", "trail\t"),
        ("in side", "in side", "in side"),
        ("semi;colon|pipe", "semi;colon|pipe", "semi;colon|pipe"),
        ("ünï 😀", "ünï 😀", "ünï 😀"),
        ("", "", ""),
    ])
    func quotesOnlyWhenNeeded(value: String, field: String, parsedValue: String) {
        let text = "id,value,end\r\n1,old,x\r\n"
        let table = parse(text)
        let edit = table.editCell(row: 1, column: 1, value: value, lineEnding: .crlf)
        #expect(edit.replacement == field)
        let result = applying([edit], to: text)
        expectChangedOnlyInside(table.rows[1].cells[1].range, original: text, result: result)
        let reparsed = parse(result)
        #expect(reparsed.rows.count == 2)
        #expect(reparsed.value(row: 1, column: 1) == parsedValue)
        #expect(reparsed.value(row: 1, column: 2) == "x")
    }

    @Test func tsvQuotesTabsButNotCommas() {
        let text = "a\tb\n1\t2\n"
        let table = parse(text, "\t")
        #expect(table.editCell(row: 1, column: 0, value: "x,y", lineEnding: .lf).replacement == "x,y")
        #expect(table.editCell(row: 1, column: 0, value: "x\ty", lineEnding: .lf).replacement == "\"x\ty\"")
    }

    @Test func padsShortRows() {
        let text = "a,b,c\nd\ne,f\n"
        let table = parse(text)
        let edit = table.editCell(row: 1, column: 2, value: "x", lineEnding: .lf)
        let result = applying([edit], to: text)
        #expect(result == "a,b,c\nd,,x\ne,f\n")
        #expect(parse(result).value(row: 1, column: 2) == "x")
        expectChangedOnlyInside(NSRange(location: 7, length: 0), original: text, result: result)
        // An empty value for a missing cell changes nothing.
        #expect(table.editCell(row: 1, column: 2, value: "", lineEnding: .lf).isEmpty)
        // A blank line gets its first cell directly.
        let blank = parse("a,b\n\nc,d\n")
        #expect(applying([blank.editCell(row: 1, column: 1, value: "y", lineEnding: .lf)], to: "a,b\n\nc,d\n") == "a,b\n,y\nc,d\n")
    }

    @Test func multiLineAndUnicodeNeighboursAreUntouched() {
        let text = "名前,note\r\n😀,\"line one\r\nline two\"\r\nJosé,\"ü\"\r\n"
        let table = parse(text)
        let target = table.rows[2].cells[1].range
        let result = applying([table.editCell(row: 2, column: 1, value: "ö", lineEnding: .crlf)], to: text)
        #expect(result == "名前,note\r\n😀,\"line one\r\nline two\"\r\nJosé,\"ö\"\r\n")
        expectChangedOnlyInside(target, original: text, result: result)
        let multiLine = table.rows[1].cells[1].range
        let edited = applying([table.editCell(row: 1, column: 1, value: "one line", lineEnding: .crlf)], to: text)
        #expect(edited == "名前,note\r\n😀,\"one line\"\r\nJosé,\"ü\"\r\n")
        expectChangedOnlyInside(multiLine, original: text, result: edited)
    }

    @Test func emptyingTheLastUnterminatedLineKeepsTheRow() {
        let text = "a\nb"
        let table = parse(text)
        let result = applying([table.editCell(row: 1, column: 0, value: "", lineEnding: .lf)], to: text)
        #expect(result == "a\n\"\"")
        #expect(parse(result).rows.count == 2)
        #expect(parse(result).value(row: 1, column: 0) == "")
        // With a final newline an empty line is a row already.
        #expect(applying([parse("a\nb\n").editCell(row: 1, column: 0, value: "", lineEnding: .lf)], to: "a\nb\n") == "a\n\n")
    }

    @Test func editingPastTheLastRowAppendsOne() {
        #expect(applying([parse("a,b\nc,d").editCell(row: 2, column: 1, value: "x", lineEnding: .lf)], to: "a,b\nc,d") == "a,b\nc,d\n,x")
        #expect(applying([parse("a,b\r\n").editCell(row: 1, column: 0, value: "x", lineEnding: .crlf)], to: "a,b\r\n") == "a,b\r\nx\r\n")
        #expect(applying([parse("").editCell(row: 0, column: 0, value: "x", lineEnding: .lf)], to: "") == "x\n")
    }

    @Test func encodedBytesChangeOnlyInTheCell() throws {
        for encoding in [TextEncoding.utf8WithBOM, .utf16LittleEndian, .windowsLatin1] {
            let original = "name;price\r\nCafé;3,50\r\nThé;\"2,00\"\r\n"
            let bytes = try TextCodec.encode(original, as: encoding)
            let decoded = try TextCodec.decode(bytes, as: encoding)
            let table = DelimitedText.parse(decoded.text as NSString, delimiter: DelimitedText.detectDelimiter(decoded.text as NSString, fileExtension: "csv"))
            #expect(table.delimiter == ";")
            let result = applying([table.editCell(row: 2, column: 1, value: "2,10", lineEnding: .crlf)], to: decoded.text)
            let newBytes = try TextCodec.encode(result, as: encoding)
            let expected = try TextCodec.encode("name;price\r\nCafé;3,50\r\nThé;\"2,10\"\r\n", as: encoding)
            #expect(newBytes == expected)
            // Only the "00" → "10" bytes differ.
            let common = zip(bytes, newBytes).prefix { $0 == $1 }.count
            let commonSuffix = zip(bytes.reversed(), newBytes.reversed()).prefix { $0 == $1 }.count
            #expect(bytes.count - common - commonSuffix <= (encoding == .utf16LittleEndian ? 2 : 1))
        }
    }
}

@Suite struct InsertRowTests {
    @Test func insertsBeforeARow() {
        let text = "a,b,c\r\nd,e,f\r\n"
        let table = parse(text)
        let edit = table.insertRow(at: 1, lineEnding: .crlf)
        #expect(edit == TextEdit(range: NSRange(location: 7, length: 0), replacement: ",,\r\n"))
        let result = applying([edit], to: text)
        #expect(result == "a,b,c\r\n,,\r\nd,e,f\r\n")
        #expect(parse(result).rows.map { $0.cells.map(\.value) } == [["a", "b", "c"], ["", "", ""], ["d", "e", "f"]])
        #expect(applying([table.insertRow(at: 0, lineEnding: .crlf)], to: text) == ",,\r\na,b,c\r\nd,e,f\r\n")
    }

    @Test func appendingKeepsTheFinalNewlineState() {
        #expect(applying([parse("a,b\nc,d\n").insertRow(at: 2, lineEnding: .lf)], to: "a,b\nc,d\n") == "a,b\nc,d\n,\n")
        let unterminated = applying([parse("a,b\rc,d").insertRow(at: 2, lineEnding: .cr)], to: "a,b\rc,d")
        #expect(unterminated == "a,b\rc,d\r,")
        #expect(parse(unterminated).rows.count == 3)
    }

    @Test func singleColumnRowsStayVisible() {
        let appended = applying([parse("a\nb").insertRow(at: 2, lineEnding: .lf)], to: "a\nb")
        #expect(appended == "a\nb\n\"\"")
        #expect(parse(appended).rows.count == 3)
        let middle = applying([parse("a\nb").insertRow(at: 1, lineEnding: .lf)], to: "a\nb")
        #expect(middle == "a\n\nb")
        #expect(parse(middle).rows.count == 3)
    }

    @Test func emptyFile() {
        let result = applying([parse("").insertRow(at: 0, lineEnding: .crlf)], to: "")
        #expect(result == "\r\n")
        #expect(parse(result).rows.count == 1)
    }

    @Test func multiLineRowsMoveAsAWhole() {
        let text = "a,\"x\ny\"\nb,c\n"
        let result = applying([parse(text).insertRow(at: 1, lineEnding: .lf)], to: text)
        #expect(result == "a,\"x\ny\"\n,\nb,c\n")
    }
}

@Suite struct DeleteRowsTests {
    @Test func deletesOneRowWithItsLineEnding() {
        let text = "a,b\r\nc,d\r\ne,f\r\n"
        let edits = parse(text).deleteRows([1])
        #expect(edits == [TextEdit(range: NSRange(location: 5, length: 5), replacement: "")])
        #expect(applying(edits, to: text) == "a,b\r\ne,f\r\n")
    }

    @Test func adjacentRowsMergeAndRunsGoLastFirst() {
        let text = "0\n1\n2\n3\n4\n5\n"
        let edits = parse(text).deleteRows([1, 2, 4, 9])
        #expect(edits.count == 2)
        expectDescending(edits)
        #expect(applying(edits, to: text) == "0\n3\n5\n")
    }

    @Test func keepsTheFinalNewlineState() {
        #expect(applying(parse("a\nb\nc\n").deleteRows([2]), to: "a\nb\nc\n") == "a\nb\n")
        #expect(applying(parse("a\nb\nc").deleteRows([2]), to: "a\nb\nc") == "a\nb")
        #expect(applying(parse("a\r\nb\r\nc").deleteRows([1, 2]), to: "a\r\nb\r\nc") == "a")
        #expect(applying(parse("a\nb\nc").deleteRows([0, 2]), to: "a\nb\nc") == "b")
        #expect(applying(parse("a\nb\nc").deleteRows([0, 1, 2]), to: "a\nb\nc") == "")
        #expect(applying(parse("a\nb\n").deleteRows([0, 1]), to: "a\nb\n") == "")
    }

    @Test func multiLineRows() {
        let text = "h\r\n\"x\r\ny\"\r\nz\r\n"
        #expect(applying(parse(text).deleteRows([1]), to: text) == "h\r\nz\r\n")
    }

    @Test func nothingToDelete() {
        #expect(parse("a\n").deleteRows([]).isEmpty)
        #expect(parse("a\n").deleteRows([3]).isEmpty)
    }
}

@Suite struct ColumnEditTests {
    let text = "a,b,c\r\n1,\"2,x\",3\r\nshort\r\n\r\n4,5,6"

    @Test func insertColumnAtEachPosition() {
        let table = parse(text)
        let first = table.insertColumn(at: 0)
        expectDescending(first)
        #expect(applying(first, to: text) == ",a,b,c\r\n,1,\"2,x\",3\r\n,short\r\n\r\n,4,5,6")
        let middle = table.insertColumn(at: 2)
        #expect(applying(middle, to: text) == "a,b,,c\r\n1,\"2,x\",,3\r\nshort\r\n\r\n4,5,,6")
        let end = table.insertColumn(at: 3)
        let appended = applying(end, to: text)
        #expect(appended == "a,b,c,\r\n1,\"2,x\",3,\r\nshort\r\n\r\n4,5,6,")
        #expect(parse(appended).columnCount == 4)
        let reparsed = parse(applying(middle, to: text))
        #expect(reparsed.rows[1].cells.map(\.value) == ["1", "2,x", "", "3"])
        #expect(reparsed.value(row: 2, column: 0) == "short")
    }

    @Test func deleteColumnAtEachPosition() {
        let table = parse(text)
        let first = table.deleteColumn(0)
        expectDescending(first)
        #expect(applying(first, to: text) == "b,c\r\n\"2,x\",3\r\n\r\n\r\n5,6")
        #expect(applying(table.deleteColumn(1), to: text) == "a,c\r\n1,3\r\nshort\r\n\r\n4,6")
        #expect(applying(table.deleteColumn(2), to: text) == "a,b\r\n1,\"2,x\"\r\nshort\r\n\r\n4,5")
        #expect(table.deleteColumn(5).isEmpty)
    }

    @Test func deleteMultiLineColumn() {
        let text = "id,note\n1,\"a\nb\"\n2,c\n"
        #expect(applying(parse(text).deleteColumn(1), to: text) == "id\n1\n2\n")
    }

    @Test func columnEditsKeepTheDelimiter() {
        let text = "a\tb\n1\t2\n"
        let table = parse(text, "\t")
        #expect(applying(table.insertColumn(at: 1), to: text) == "a\t\tb\n1\t\t2\n")
        #expect(applying(table.deleteColumn(0), to: text) == "b\n2\n")
    }
}
