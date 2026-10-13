import Foundation
import QuickEditCore
import Testing

@Suite struct RiskyCharactersTests {
    @Test(arguments: [
        (0x200B, RiskyCategory.zeroWidth), (0x200C, .zeroWidth), (0x200D, .zeroWidth), (0x2060, .zeroWidth),
        (0x2062, .zeroWidth), (0x180E, .zeroWidth), (0xE0041, .zeroWidth),
        (0x202A, .bidiControl), (0x202E, .bidiControl), (0x2066, .bidiControl), (0x2069, .bidiControl),
        (0x200E, .bidiControl), (0x200F, .bidiControl), (0x061C, .bidiControl),
        (0x00A0, .unusualSpace), (0x2000, .unusualSpace), (0x200A, .unusualSpace), (0x202F, .unusualSpace),
        (0x205F, .unusualSpace), (0x3000, .unusualSpace), (0x1680, .unusualSpace), (0x3164, .unusualSpace),
        (0x00AD, .softHyphen),
        (0x0000, .control), (0x0008, .control), (0x000B, .control), (0x000C, .control), (0x001B, .control),
        (0x007F, .control), (0x0085, .control), (0x009F, .control),
        (0xFEFF, .byteOrderMark), (0x2028, .lineSeparator), (0x2029, .lineSeparator),
    ] as [(UInt32, RiskyCategory)])
    func risky(value: UInt32, category: RiskyCategory) {
        #expect(RiskyCharacters.isRisky(Unicode.Scalar(value)!) == category)
    }

    @Test(arguments: [0x09, 0x0A, 0x0D, 0x20, 0x41, 0xE9, 0x4E2D, 0x1F600, 0xFE0F, 0x2010, 0x2065, 0xE0080] as [UInt32])
    func safe(value: UInt32) {
        #expect(RiskyCharacters.isRisky(Unicode.Scalar(value)!) == nil)
    }

    @Test func scanReportsUTF16Ranges() {
        let text = "a\u{200B}b\u{202E}c\u{00A0}" as NSString
        let found = RiskyCharacters.scan(text, in: NSRange(location: 0, length: text.length))
        #expect(found.map(\.range) == [NSRange(location: 1, length: 1), NSRange(location: 3, length: 1), NSRange(location: 5, length: 1)])
        #expect(found.map(\.category) == [.zeroWidth, .bidiControl, .unusualSpace])
        #expect(found[0].name == "ZERO WIDTH SPACE U+200B")
        #expect(found[1].name == "RIGHT-TO-LEFT OVERRIDE U+202E")
    }

    @Test func surrogatePairsShiftRangesAndCanBeRisky() {
        // 😀 is two UTF-16 units; the tag character U+E0041 is risky and also two units.
        let text = "😀\u{200B}x\u{E0041}y" as NSString
        let found = RiskyCharacters.scan(text, in: NSRange(location: 0, length: text.length))
        #expect(found.map(\.range) == [NSRange(location: 2, length: 1), NSRange(location: 4, length: 2)])
        #expect(found[1].scalar == "\u{E0041}")
        #expect(found[1].name == "TAG LATIN CAPITAL LETTER A U+E0041")
    }

    @Test func rangesCuttingSurrogatePairs() {
        let text = "\u{E0041}x" as NSString
        // Starting at the trail surrogate: the pair belongs to the previous range.
        #expect(RiskyCharacters.scan(text, in: NSRange(location: 1, length: 2)).isEmpty)
        // Ending after the lead surrogate: the pair is completed by looking ahead.
        #expect(RiskyCharacters.scan(text, in: NSRange(location: 0, length: 1)).map(\.range) == [NSRange(location: 0, length: 2)])
    }

    @Test func lonelySurrogatesAreIgnored() {
        let units: [UInt16] = [0xD83D, 0x41, 0xDE00, 0x200B]
        let text = NSString(characters: units, length: units.count)
        #expect(RiskyCharacters.scan(text, in: NSRange(location: 0, length: text.length)).map(\.range) == [NSRange(location: 3, length: 1)])
    }

    @Test func scanOnlyLooksInsideTheRange() {
        let text = "\u{200B}abc\u{200B}def\u{200B}" as NSString
        #expect(RiskyCharacters.scan(text, in: NSRange(location: 1, length: 5)).map(\.range) == [NSRange(location: 4, length: 1)])
        #expect(RiskyCharacters.scan(text, in: NSRange(location: 6, length: 100)).map(\.range) == [NSRange(location: 8, length: 1)])
        #expect(RiskyCharacters.scan(text, in: NSRange(location: 50, length: 10)).isEmpty)
        #expect(RiskyCharacters.scan(text, in: NSRange(location: NSNotFound, length: 0)).isEmpty)
        #expect(RiskyCharacters.scan("" as NSString, in: NSRange(location: 0, length: 0)).isEmpty)
    }

    @Test func controlCharacterNames() {
        let text = "\u{0}\u{1B}\u{7F}\u{85}\u{C}" as NSString
        let names = RiskyCharacters.scan(text, in: NSRange(location: 0, length: text.length)).map(\.name)
        #expect(names == ["NULL U+0000", "ESCAPE U+001B", "DELETE U+007F", "NEXT LINE U+0085", "FORM FEED U+000C"])
    }

    @Test func countWholeString() {
        let text = "let a\u{00A0}= 1\u{FEFF}\r\n\tb\u{2028}c\u{E0001}\u{AD}" as NSString
        #expect(RiskyCharacters.count(in: text) == 5)
        #expect(RiskyCharacters.count(in: "plain\tascii\r\ntext\n" as NSString) == 0)
    }

    @Test func chunkBoundariesInEveryStringRepresentation() {
        // Puts a risky surrogate pair across the 16K scanning chunk boundary.
        let prefix = String(repeating: "a", count: 16_383)
        let source = prefix + "\u{E0041}" + String(repeating: "é", count: 20_000) + "\u{200B}"
        let representations: [NSString] = [source as NSString, NSMutableString(string: source), NSString(string: source)]
        for text in representations {
            #expect(RiskyCharacters.count(in: text) == 2)
            let found = RiskyCharacters.scan(text, in: NSRange(location: 0, length: text.length))
            #expect(found.map(\.range) == [NSRange(location: 16_383, length: 2), NSRange(location: 36_385, length: 1)])
        }
    }
}
