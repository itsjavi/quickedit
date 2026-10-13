import Foundation
import QuickEditCore
import Testing

/// `LineIndex` and `RiskyIndex` updated edit by edit always match a scan of the whole text.
@Suite struct IncrementalIndexTests {
    /// Pieces that stress the edges: CR LF pairs that edits split or join, other line breaks, surrogate pairs and
    /// risky characters (a zero-width space, a tag character outside the BMP).
    private static let pieces = ["a", "bc", "\n", "\r", "\r\n", "\u{2028}", "\u{85}", "é", "😀", "\u{200B}", "\u{E0041}", "  "]

    /// `NSString.getLineStart`, the definition the index follows.
    private static func referenceStarts(_ text: NSString) -> [Int] {
        var result = [0]
        var index = 0
        while index < text.length {
            var end = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
            if end > contentsEnd { result.append(end) }
            index = end
        }
        return result
    }

    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    private static func randomText(_ generator: inout Generator, pieces count: Int) -> String {
        (0..<count).map { _ in Self.pieces.randomElement(using: &generator)! }.joined()
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8])
    func randomEditsMatchAFullScan(seed: UInt64) {
        var generator = Generator(state: seed &* 0x9E37_79B9_7F4A_7C15)
        let text = NSMutableString(string: Self.randomText(&generator, pieces: 40))
        let lines = LineIndex()
        let risky = RiskyIndex()
        _ = lines.lineStarts(in: text)
        risky.rebuild(text)
        for step in 0..<400 {
            // Any UTF-16 range, even one that cuts a surrogate pair or a CRLF in half.
            let location = Int.random(in: 0...text.length, using: &generator)
            let length = Int.random(in: 0...min(6, text.length - location), using: &generator)
            let replacement = Bool.random(using: &generator) ? "" : Self.randomText(&generator, pieces: Int.random(in: 1...4, using: &generator))
            text.replaceCharacters(in: NSRange(location: location, length: length), with: replacement)
            let inserted = (replacement as NSString).length
            let edited = NSRange(location: location, length: inserted)
            lines.edit(editedRange: edited, changeInLength: inserted - length, in: text)
            risky.edit(editedRange: edited, changeInLength: inserted - length, in: text)

            let expectedLines = Self.referenceStarts(text)
            let expectedRisky = RiskyCharacters.scan(text, in: NSRange(location: 0, length: text.length)).map(\.range.location)
            guard lines.lineStarts(in: text) == expectedLines, risky.locations == expectedRisky else {
                Issue.record("Seed \(seed), step \(step): \(String(text).debugDescription)")
                #expect(lines.lineStarts(in: text) == expectedLines)
                #expect(risky.locations == expectedRisky)
                return
            }
        }
    }

    @Test func fullBuildMatchesGetLineStart() {
        var generator = Generator(state: 42)
        // Longer than a scanning chunk, so chunk edges (and a CRLF across one) are covered for strings that don't
        // expose their characters directly.
        let text = NSMutableString(string: Self.randomText(&generator, pieces: 60_000))
        #expect(LineIndex().lineStarts(in: text) == Self.referenceStarts(text))
    }

    @Test func lineLookups() {
        let text = "one\r\ntwo\rthree\n" as NSString
        let index = LineIndex()
        #expect(index.lineStarts(in: text) == [0, 5, 9, 15])
        #expect(index.line(of: 0, in: text) == 0)
        #expect(index.line(of: 4, in: text) == 0)
        #expect(index.line(of: 5, in: text) == 1)
        #expect(index.line(of: 15, in: text) == 3)
        #expect(index.start(ofLine: 2, in: text) == 9)
        #expect(index.start(ofLine: 99, in: text) == 15)
    }
}
