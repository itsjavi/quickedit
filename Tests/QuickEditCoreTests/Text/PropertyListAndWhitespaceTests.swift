import Foundation
import QuickEditCore
import Testing

@Suite struct PropertyListTextTests {
    private let plist: [String: Any] = ["name": "QuickEdit", "count": 3, "enabled": true, "items": ["a", "b"]]

    @Test func detectsBinaryPropertyLists() throws {
        let binary = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        #expect(PropertyListText.isBinaryPropertyList(binary))
        #expect(!PropertyListText.isBinaryPropertyList(xml))
        #expect(!PropertyListText.isBinaryPropertyList(Data("bplist".utf8)))
        #expect(!PropertyListText.isBinaryPropertyList(Data("bplistXY".utf8)))
        #expect(!PropertyListText.isBinaryPropertyList(Data()))
    }

    @Test func convertsToXML() throws {
        let binary = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let xml = try PropertyListText.xmlText(fromBinary: binary)
        #expect(xml.hasPrefix("<?xml"))
        #expect(xml.contains("<key>name</key>"))
        #expect(xml.contains("<string>QuickEdit</string>"))
        let reparsed = try PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as? NSDictionary
        #expect(reparsed == plist as NSDictionary)
    }

    @Test func corruptBinaryThrows() {
        #expect(throws: (any Error).self) { try PropertyListText.xmlText(fromBinary: Data("bplist00garbage".utf8)) }
    }
}

@Suite struct WhitespaceTransformsTests {
    @Test func trimsBeforeEveryKindOfLineBreak() {
        let text = "a  \nb\t\r\nc \t \rd  "
        #expect(Array(WhitespaceTransforms.trimmingTrailingWhitespace(text).utf8) == Array("a\nb\r\nc\rd".utf8))
    }

    @Test func keepsInnerAndUnicodeWhitespace() {
        let text = "  indented  inner\u{00A0}\n\u{C}\ntab\tx\n😀 \n"
        #expect(WhitespaceTransforms.trimmingTrailingWhitespace(text) == "  indented  inner\u{00A0}\n\u{C}\ntab\tx\n😀\n")
    }

    @Test func unchangedTextIsReturnedAsIs() {
        let text = "clean\r\nlines\n"
        #expect(Array(WhitespaceTransforms.trimmingTrailingWhitespace(text).utf8) == Array(text.utf8))
        #expect(WhitespaceTransforms.trimmingTrailingWhitespace("") == "")
        #expect(WhitespaceTransforms.trimmingTrailingWhitespace("   ") == "")
    }

    @Test func finalNewline() {
        #expect(WhitespaceTransforms.ensuringFinalNewline("", lineEnding: .lf) == "")
        #expect(Array(WhitespaceTransforms.ensuringFinalNewline("a", lineEnding: .crlf).utf8) == Array("a\r\n".utf8))
        #expect(WhitespaceTransforms.ensuringFinalNewline("a", lineEnding: .cr) == "a\r")
        #expect(WhitespaceTransforms.ensuringFinalNewline("a\n", lineEnding: .crlf) == "a\n")
        #expect(WhitespaceTransforms.ensuringFinalNewline("a\r", lineEnding: .lf) == "a\r")
        #expect(Array(WhitespaceTransforms.ensuringFinalNewline("a\r\n", lineEnding: .lf).utf8) == Array("a\r\n".utf8))
    }
}
