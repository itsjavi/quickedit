import Foundation
@testable import QuickEditSyntax
import Testing

/// Typing into (or table-editing) a file that starts empty must highlight like a freshly opened one.
@Suite struct EmptyDocumentEditTests {
    private func typeIn(_ languageID: String, chunks: [String]) -> (incremental: [SyntaxToken], fresh: [SyntaxToken]) {
        let language = LanguageRegistry.language(id: languageID)!
        let text = NSMutableString()
        let highlighter = SyntaxHighlighter(language: language)
        highlighter.setText(text)
        _ = highlighter.tokens(in: NSRange(location: 0, length: 0))
        for chunk in chunks {
            let location = text.length
            text.insert(chunk, at: location)
            highlighter.applyEdit(replacing: NSRange(location: location, length: 0), with: (chunk as NSString).length, in: text)
            _ = highlighter.tokens(in: NSRange(location: 0, length: text.length))
        }
        let fresh = SyntaxHighlighter(language: language)
        fresh.setText(text)
        return (highlighter.tokens(in: NSRange(location: 0, length: text.length)), fresh.tokens(in: NSRange(location: 0, length: text.length)))
    }

    @Test(arguments: ["csv", "typescript", "json"])
    func typingIntoAnEmptyFile(_ id: String) {
        let chunks = id == "csv" ? ["asds,,,,\n", "b,,,,\n", "asdsd,,sdsd,,\n", "sdsd,,,,"]
            : id == "json" ? ["{", "\"a\"", ": ", "1", "}"] : ["const ", "a", " = ", "\"x\"", ";\n"]
        let result = typeIn(id, chunks: chunks)
        #expect(!result.fresh.isEmpty)
        #expect(result.incremental == result.fresh)
    }

    @Test func characterByCharacterCSV() {
        let result = typeIn("csv", chunks: "name,age\nAna,31\n".map(String.init))
        #expect(result.incremental == result.fresh)
        #expect(result.fresh.contains { if case .column(1) = $0.kind { true } else { false } })
    }
}
