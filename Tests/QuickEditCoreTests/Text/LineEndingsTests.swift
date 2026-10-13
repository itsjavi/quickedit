import Foundation
import QuickEditCore
import Testing

@Suite struct LineEndingsTests {
    @Test func detectsEachKind() {
        #expect(LineEndings.detect("a\nb\nc") == LineEndingInfo(dominant: .lf, isMixed: false, counts: [.lf: 2, .crlf: 0, .cr: 0]))
        #expect(LineEndings.detect("a\r\nb\r\n") == LineEndingInfo(dominant: .crlf, isMixed: false, counts: [.lf: 0, .crlf: 2, .cr: 0]))
        #expect(LineEndings.detect("a\rb\r") == LineEndingInfo(dominant: .cr, isMixed: false, counts: [.lf: 0, .crlf: 0, .cr: 2]))
    }

    @Test func noLineBreaksIsLF() {
        for text in ["", "abc", "héllo 😀"] {
            #expect(LineEndings.detect(text) == LineEndingInfo(dominant: .lf, isMixed: false, counts: [.lf: 0, .crlf: 0, .cr: 0]))
        }
    }

    @Test func mixedEndingsAreFlagged() {
        let info = LineEndings.detect("a\r\nb\nc\r\nd\re")
        #expect(info.dominant == .crlf)
        #expect(info.isMixed)
        #expect(info.counts == [.lf: 1, .crlf: 2, .cr: 1])
    }

    @Test func tiesPreferLFThenCRLF() {
        #expect(LineEndings.detect("a\nb\r\n").dominant == .lf)
        #expect(LineEndings.detect("a\rb\r\n").dominant == .crlf)
    }

    @Test func crBeforeCRLFIsSeparate() {
        // "\r\r\n" is a CR followed by a CRLF, not two CRs and an LF.
        #expect(LineEndings.detect("a\r\r\nb").counts == [.lf: 0, .crlf: 1, .cr: 1])
    }

    @Test func convertsEveryKind() {
        let mixed = "héllo\r\nwörld\nüber\r😀\r\n"
        #expect(Array(LineEndings.convert(mixed, to: .lf).utf8) == Array("héllo\nwörld\nüber\n😀\n".utf8))
        #expect(Array(LineEndings.convert(mixed, to: .crlf).utf8) == Array("héllo\r\nwörld\r\nüber\r\n😀\r\n".utf8))
        #expect(Array(LineEndings.convert(mixed, to: .cr).utf8) == Array("héllo\rwörld\rüber\r😀\r".utf8))
    }

    @Test func convertKeepsTextWithoutBreaksAndUniformText() {
        #expect(LineEndings.convert("no breaks", to: .crlf) == "no breaks")
        let crlf = "a\r\nb\r\n"
        #expect(Array(LineEndings.convert(crlf, to: .crlf).utf8) == Array(crlf.utf8))
        #expect(Array(LineEndings.convert("a\nb", to: .crlf).utf8) == Array("a\r\nb".utf8))
    }

    @Test func displayNames() {
        #expect(LineEnding.allCases.map(\.displayName) == ["LF", "CRLF", "CR"])
    }

    @Test func convertedFileRoundTripsThroughTheCodec() throws {
        let bytes = Data("one\r\ntwo\r\nthree\r\n".utf8)
        let decoded = try TextCodec.decode(bytes)
        let unix = LineEndings.convert(decoded.text, to: .lf)
        let back = LineEndings.convert(unix, to: LineEndings.detect(decoded.text).dominant)
        #expect(try TextCodec.encode(back, as: decoded.encoding) == bytes)
    }
}
