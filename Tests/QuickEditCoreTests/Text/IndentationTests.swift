import Foundation
import QuickEditCore
import Testing

@Suite struct IndentationDetectorTests {
    @Test func tabs() {
        let text = "func a() {\n\tif x {\n\t\treturn\n\t}\n}\n"
        #expect(IndentationDetector.detect(text) == .tabs(width: 4))
        #expect(IndentationDetector.detect(text, tabWidth: 8) == .tabs(width: 8))
    }

    @Test(arguments: [2, 4, 8])
    func spaces(width: Int) {
        let unit = String(repeating: " ", count: width)
        let text = """
        root:
        \(unit)child:
        \(unit)\(unit)leaf: 1
        \(unit)\(unit)leaf: 2
        \(unit)other: 3
        top: 4
        \(unit)again: 5

        """
        #expect(IndentationDetector.detect(text) == .spaces(width))
    }

    @Test func multiLevelDedentsDontWinOverSingleSteps() {
        let text = "a\n    b\n        c\n            d\ne\n    f\n        g\nh\n"
        #expect(IndentationDetector.detect(text) == .spaces(4))
    }

    @Test func blockCommentContinuationsAreIgnored() {
        let text = """
        /**
         * Doc comment.
         * More.
         */
        class A {
            int b;
            /**
             * Nested doc.
             */
            void c() {
                d();
            }
        }

        """
        #expect(IndentationDetector.detect(text) == .spaces(4))
    }

    @Test func blankAndWhitespaceOnlyLinesAreIgnored() {
        let text = "a\n  b\n\n        \n  c\n    d\n"
        #expect(IndentationDetector.detect(text) == .spaces(2))
    }

    @Test func noIndentedLines() {
        #expect(IndentationDetector.detect("") == nil)
        #expect(IndentationDetector.detect("a\nb\n\nc") == nil)
    }

    @Test func majorityWins() {
        #expect(IndentationDetector.detect("a\n\tb\n\tc\n    d\n") == .tabs())
        #expect(IndentationDetector.detect("a\n\tb\n    c\n    d\n") == .spaces(4))
    }

    @Test func crlfAndCRFiles() {
        #expect(IndentationDetector.detect("a\r\n  b\r\n    c\r\n") == .spaces(2))
        #expect(IndentationDetector.detect("a\r\tb\r\t\tc\r") == .tabs())
    }

    @Test func unit() {
        #expect(Indentation.tabs().unit == "\t")
        #expect(Indentation.spaces(2).unit == "  ")
        #expect(Indentation(style: .spaces, width: 0).width == 1)
    }
}

@Suite struct IndentationConvertTests {
    @Test func spacesToTabs() {
        let text = "a\n    b\n        c\n      aligned\n"
        let result = IndentationDetector.convert(text, from: .spaces(4), to: .tabs(width: 4))
        #expect(result == "a\n\tb\n\t\tc\n\t  aligned\n")
    }

    @Test func tabsToSpaces() {
        let text = "a\n\tb\n\t\tc\t// inner tab stays\n"
        #expect(IndentationDetector.convert(text, from: .tabs(width: 4), to: .spaces(2)) == "a\n  b\n    c\t// inner tab stays\n")
    }

    @Test func twoToFourSpacesKeepsLevels() {
        #expect(IndentationDetector.convert("a\n  b\n    c\n   odd\n", from: .spaces(2), to: .spaces(4)) == "a\n    b\n        c\n     odd\n")
    }

    @Test func mixedLeadingWhitespaceUsesTabStops() {
        // A tab after two spaces reaches column 4, one level.
        #expect(IndentationDetector.convert("  \tx\n", from: .spaces(4), to: .tabs()) == "\tx\n")
    }

    @Test func lineEndingsAndContentAreUntouched() {
        let text = "a\r\n    b\r    c \t\n\n    \r\n    é😀\r\n"
        let result = IndentationDetector.convert(text, from: .spaces(4), to: .tabs())
        #expect(Array(result.utf8) == Array("a\r\n\tb\r\tc \t\n\n\t\r\n\té😀\r\n".utf8))
        let back = IndentationDetector.convert(result, from: .tabs(), to: .spaces(4))
        #expect(Array(back.utf8) == Array(text.utf8))
    }

    @Test func sameIndentationIsANoOp() {
        let text = "a\n  b\n"
        #expect(IndentationDetector.convert(text, from: .spaces(2), to: .spaces(2)) == text)
    }
}
