import Foundation
import Testing

@testable import QuickEditSyntax

@Suite("CSV and TSV columns")
struct DelimitedTests {
    @Test("CSV fields become rainbow columns, quotes included")
    func csv() {
        let h = Highlighted("name,age,\"city, state\"\nAnn,30,\"NY, \"\"NY\"\"\"\n,,x\r\nlast", language: "csv")
        #expect(h.kind(of: "name") == .column(0), "\(h.dump)")
        #expect(h.kind(of: "age") == .column(1))
        #expect(h.kind(of: "\"city, state\"") == .column(2))
        #expect(h.kind(of: "Ann") == .column(0))
        #expect(h.kind(of: "30") == .column(1))
        #expect(h.kind(of: "\"NY, \"\"NY\"\"\"") == .column(2))
        #expect(h.kind(of: "x") == .column(2))
        #expect(h.kind(of: "last") == .column(0))
        // Delimiters and line breaks aren't tokens.
        #expect(h.kinds(within: ",").isEmpty)
        #expect(h.kinds(within: "\r\n").isEmpty)
    }

    @Test("quoted fields can span lines")
    func multilineField() {
        let h = Highlighted("a,\"two\nlines\",c\n", language: "csv")
        #expect(h.kind(of: "\"two\nlines\"") == .column(1), "\(h.dump)")
        #expect(h.kind(of: "c") == .column(2))
    }

    @Test("TSV splits on tabs only")
    func tsv() {
        let h = Highlighted("a,b\tc d\te\n", language: "tsv")
        #expect(h.kind(of: "a,b") == .column(0), "\(h.dump)")
        #expect(h.kind(of: "c d") == .column(1))
        #expect(h.kind(of: "e") == .column(2))
    }

    @Test("a range in the middle of a line keeps the line's column numbering")
    func partialRange() {
        let text = "aa,bb,cc\ndd,ee,ff\n" as NSString
        let highlighter = SyntaxHighlighter(language: LanguageRegistry.language(id: "csv")!)
        highlighter.setText(text)
        let tokens = highlighter.tokens(in: NSRange(location: 4, length: 9))  // "b,cc\ndd,e"
        #expect(tokens.map(\.kind) == [.column(1), .column(2), .column(0), .column(1)])
        #expect(tokens.first?.range == NSRange(location: 4, length: 1))
        #expect(tokens.last?.range == NSRange(location: 12, length: 1))
    }

    @Test("edits invalidate the edited lines")
    func edits() {
        let highlighter = SyntaxHighlighter(language: LanguageRegistry.language(id: "csv")!)
        highlighter.setText("a,b\nc,d\ne,f\n")
        let newText = "a,b\nc,x,d\ne,f\n" as NSString
        let changed = highlighter.applyEdit(replacing: NSRange(location: 6, length: 0), with: 2, in: newText)
        #expect(changed == [NSRange(location: 4, length: 6)])
        let tokens = highlighter.tokens(in: NSRange(location: 4, length: 6))
        #expect(tokens.map(\.kind) == [.column(0), .column(1), .column(2)])
    }
}

@Suite("Callers passing one mutable string")
struct MutableStringTests {
    @Test("edits work when the same NSMutableString is passed every time", arguments: ["csv", "typescript", "markdown"])
    func sharedMutableString(language id: String) {
        let storage = NSMutableString(string: "a,\"b\",c\nconst x = 1; // `code`\n")
        let highlighter = SyntaxHighlighter(language: LanguageRegistry.language(id: id)!)
        highlighter.setText(storage)
        _ = highlighter.tokens(in: NSRange(location: 0, length: storage.length))
        // Delete the tail, then insert, mutating the same object before each applyEdit.
        let tail = NSRange(location: storage.length - 8, length: 8)
        storage.deleteCharacters(in: tail)
        highlighter.applyEdit(replacing: tail, with: 0, in: storage)
        storage.insert("\"q\",", at: 0)
        highlighter.applyEdit(replacing: NSRange(location: 0, length: 0), with: 4, in: storage)
        let fresh = SyntaxHighlighter(language: LanguageRegistry.language(id: id)!)
        fresh.setText(storage.copy() as! NSString)
        let all = NSRange(location: 0, length: storage.length)
        #expect(highlighter.tokens(in: all) == fresh.tokens(in: all))
    }
}
