import Foundation
import QuickEditCore
import Testing

struct CSVFixture: CustomTestStringConvertible, Sendable {
    let name: String
    let text: String
    let delimiter: Character
    var testDescription: String { name }

    static let all: [CSVFixture] = [
        CSVFixture(name: "empty", text: "", delimiter: ","),
        CSVFixture(name: "only a newline", text: "\n", delimiter: ","),
        CSVFixture(name: "simple LF", text: "a,b,c\n1,2,3\n", delimiter: ","),
        CSVFixture(name: "CRLF", text: "a,b,c\r\n1,2,3\r\n", delimiter: ","),
        CSVFixture(name: "CR", text: "a,b\rc,d\r", delimiter: ","),
        CSVFixture(name: "mixed endings", text: "a,b\r\nc,d\ne,f\rg,h", delimiter: ","),
        CSVFixture(name: "no final newline", text: "a,b\nc,d", delimiter: ","),
        CSVFixture(name: "trailing empty lines", text: "a,b\n\n\n", delimiter: ","),
        CSVFixture(name: "quoted delimiters", text: "name,list\n\"Smith, J\",\"a,b,c\"\n", delimiter: ","),
        CSVFixture(name: "escaped quotes", text: "\"he said \"\"hi\"\"\",\"\"\"\"\n", delimiter: ","),
        CSVFixture(name: "multi-line quoted cell", text: "id,note\r\n1,\"line one\r\nline two\nline three\"\r\n2,x\r\n", delimiter: ","),
        CSVFixture(name: "unicode", text: "名前,😀\r\nJosé,\"ü,👍🏽\"\r\n", delimiter: ","),
        CSVFixture(name: "ragged rows", text: "a,b,c\nd\ne,f\n,,,,\n", delimiter: ","),
        CSVFixture(name: "spaces around fields", text: "a , b ,\" c\" , d\n", delimiter: ","),
        CSVFixture(name: "trailing delimiter", text: "a,\n,\n", delimiter: ","),
        CSVFixture(name: "unterminated quote", text: "a,\"bc\nd,e", delimiter: ","),
        CSVFixture(name: "text after closing quote", text: "\"a\"b,c\n", delimiter: ","),
        CSVFixture(name: "quote inside unquoted field", text: "5\" disk,x\n", delimiter: ","),
        CSVFixture(name: "leading BOM character", text: "\u{FEFF}a,b\n", delimiter: ","),
        CSVFixture(name: "TSV", text: "a\tb\t\"c\td\"\n1\t\t3\n", delimiter: "\t"),
        CSVFixture(name: "semicolons", text: "x;y\n1,5;2,25\n", delimiter: ";"),
        CSVFixture(name: "pipes", text: "x|y|z\n1|2|3", delimiter: "|"),
    ]
}

/// Rebuilds the text from the parsed ranges alone: rows and line endings must tile the text, and cells must be the
/// row split at single delimiters.
func reconstruct(_ text: NSString, _ parsed: DelimitedText) -> String {
    var output = ""
    var expectedLocation = 0
    for row in parsed.rows {
        #expect(row.range.location == expectedLocation)
        #expect(row.lineEnding.location == row.range.upperBound)
        #expect(!row.cells.isEmpty)
        #expect(row.cells.first?.range.location == row.range.location)
        #expect(row.cells.last?.range.upperBound == row.range.upperBound)
        for (cell, next) in zip(row.cells, row.cells.dropFirst()) {
            #expect(next.range.location == cell.range.upperBound + 1)
            #expect(text.substring(with: NSRange(location: cell.range.upperBound, length: 1)) == String(parsed.delimiter))
        }
        output += text.substring(with: row.range) + text.substring(with: row.lineEnding)
        expectedLocation = row.lineEnding.upperBound
    }
    #expect(expectedLocation == text.length)
    return output
}

@Suite struct DelimitedTextParseTests {
    @Test(arguments: CSVFixture.all)
    func rangesReproduceTheTextExactly(_ fixture: CSVFixture) {
        let text = fixture.text as NSString
        let parsed = DelimitedText.parse(text, delimiter: fixture.delimiter)
        #expect(Array(reconstruct(text, parsed).utf16) == Array(fixture.text.utf16))
    }

    @Test(arguments: CSVFixture.all)
    func bytesSurviveDecodeParseEncode(_ fixture: CSVFixture) throws {
        for encoding in [TextEncoding.utf8, .utf8WithBOM, .utf16LittleEndian] {
            let bytes = try TextCodec.encode(fixture.text, as: encoding)
            let decoded = try TextCodec.decode(bytes)
            let text = NSMutableString(string: decoded.text)
            let parsed = DelimitedText.parse(text, delimiter: fixture.delimiter)
            let rebuilt = reconstruct(text, parsed)
            #expect(try TextCodec.encode(rebuilt, as: decoded.encoding) == bytes)
        }
    }

    @Test func emptyText() {
        let parsed = DelimitedText.parse("" as NSString, delimiter: ",")
        #expect(parsed.rows.isEmpty)
        #expect(parsed.columnCount == 0)
        #expect(parsed.value(row: 0, column: 0) == "")
    }

    @Test func quotedDelimitersAndEscapes() {
        let parsed = DelimitedText.parse("a,\"b,c\",\"say \"\"hi\"\"\",\"\"\n" as NSString, delimiter: ",")
        let cells = parsed.rows[0].cells
        #expect(cells.map(\.value) == ["a", "b,c", "say \"hi\"", ""])
        #expect(cells.map(\.isQuoted) == [false, true, true, true])
        #expect(cells.map(\.range) == [NSRange(location: 0, length: 1), NSRange(location: 2, length: 5), NSRange(location: 8, length: 12), NSRange(location: 21, length: 2)])
    }

    @Test func multiLineCells() {
        let text = "id,note\r\n1,\"line one\r\nline two\"\r\n2,x\r\n" as NSString
        let parsed = DelimitedText.parse(text, delimiter: ",")
        #expect(parsed.rows.count == 3)
        #expect(parsed.value(row: 1, column: 1) == "line one\r\nline two")
        #expect(parsed.rows[1].lineEnding == NSRange(location: 31, length: 2))
        #expect(parsed.value(row: 2, column: 0) == "2")
    }

    @Test func lineEndingKinds() {
        let parsed = DelimitedText.parse("a\r\nb\nc\rd" as NSString, delimiter: ",")
        #expect(parsed.rows.map(\.lineEnding.length) == [2, 1, 1, 0])
        #expect(parsed.rows.map { $0.cells[0].value } == ["a", "b", "c", "d"])
    }

    @Test func raggedRowsAndBlankLines() {
        let parsed = DelimitedText.parse("a,b,c\nd\n\ne,f\n" as NSString, delimiter: ",")
        #expect(parsed.rows.map(\.cells.count) == [3, 1, 1, 2])
        #expect(parsed.columnCount == 3)
        #expect(parsed.rows.map(\.isBlank) == [false, false, true, false])
        #expect(parsed.value(row: 1, column: 2) == "")
        #expect(parsed.value(row: 9, column: 0) == "")
    }

    @Test func unicodeRangesAreUTF16() {
        let parsed = DelimitedText.parse("名前,😀,x\n" as NSString, delimiter: ",")
        #expect(parsed.rows[0].cells.map(\.range) == [NSRange(location: 0, length: 2), NSRange(location: 3, length: 2), NSRange(location: 6, length: 1)])
        #expect(parsed.rows[0].cells.map(\.value) == ["名前", "😀", "x"])
    }

    @Test func lenientQuoting() {
        let spaces = DelimitedText.parse("a , b ,\" c\" , d" as NSString, delimiter: ",")
        #expect(spaces.rows[0].cells.map(\.value) == ["a ", " b ", " c ", " d"])
        #expect(spaces.rows[0].cells.map(\.isQuoted) == [false, false, true, false])
        let trailing = DelimitedText.parse("\"a\"b,c" as NSString, delimiter: ",")
        #expect(trailing.rows[0].cells.map(\.value) == ["ab", "c"])
        let inner = DelimitedText.parse("5\" disk,x" as NSString, delimiter: ",")
        #expect(inner.rows[0].cells.map(\.value) == ["5\" disk", "x"])
        #expect(inner.rows[0].cells[0].isQuoted == false)
        let unterminated = DelimitedText.parse("a,\"bc\nd,e" as NSString, delimiter: ",")
        #expect(unterminated.rows.count == 1)
        #expect(unterminated.rows[0].cells.map(\.value) == ["a", "bc\nd,e"])
    }

    @Test func trailingDelimiterMakesAnEmptyCell() {
        let parsed = DelimitedText.parse("a,\n," as NSString, delimiter: ",")
        #expect(parsed.rows.map { $0.cells.map(\.value) } == [["a", ""], ["", ""]])
    }

    @Test func tabsAndOtherDelimiters() {
        let tsv = DelimitedText.parse("a\tb,c\t\"d\te\"" as NSString, delimiter: "\t")
        #expect(tsv.rows[0].cells.map(\.value) == ["a", "b,c", "d\te"])
        let semicolons = DelimitedText.parse("1,5;2,25" as NSString, delimiter: ";")
        #expect(semicolons.rows[0].cells.map(\.value) == ["1,5", "2,25"])
    }
}

@Suite struct DelimiterDetectionTests {
    @Test func extensionDecidesTSV() {
        #expect(DelimitedText.detectDelimiter("a,b,c\n1,2,3\n" as NSString, fileExtension: "tsv") == "\t")
        #expect(DelimitedText.detectDelimiter("a,b\n" as NSString, fileExtension: "TAB") == "\t")
    }

    @Test(arguments: [
        ("a,b,c\n1,2,3\n4,5,6\n", Character(",")),
        ("a;b;c\n1,5;2,5;3\n4;5;6\n", ";"),
        ("x;y\n1,5;2,25\n3,75;4\n", ";"),
        ("a|b|c\n1|2|3\n", "|"),
        ("a\tb\tc\n1\t2\t3\n", "\t"),
        ("\"a,b,c\";d\n\"e,f\";g\n\"h\";i\n", ";"),
        ("\"multi\nline, with commas\";x\ny;z\n", ";"),
        ("single column\nvalues\n", ","),
        ("", ","),
        ("a,b;c\n1,2;3\n4,5;6\n", ","),
    ])
    func sniffs(text: String, expected: Character) {
        #expect(DelimitedText.detectDelimiter(text as NSString, fileExtension: "csv") == expected)
        #expect(DelimitedText.detectDelimiter(text as NSString, fileExtension: nil) == expected)
    }
}
