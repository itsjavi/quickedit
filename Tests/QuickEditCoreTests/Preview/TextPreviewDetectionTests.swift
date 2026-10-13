import Foundation
@testable import QuickEditCore
import Testing

@Suite struct TextPreviewDetectionTests {
    private func classify(_ bytes: [UInt8], truncated: Bool = false) -> TextPreviewDetection.Result {
        TextPreviewDetection.classify(Data(bytes), isTruncated: truncated)
    }

    private func text(_ result: TextPreviewDetection.Result) -> TextPreview? {
        if case .text(let preview) = result { return preview }
        return nil
    }

    /// `count` transport stream packets: a PAT header, then null packets padded with 0xFF stuffing.
    private func transportStream(packets count: Int, packetSize: Int = 188, syncOffset: Int = 0) -> [UInt8] {
        var bytes: [UInt8] = []
        for index in 0..<count {
            var packet = [UInt8](repeating: 0xFF, count: packetSize)
            let header: [UInt8] = index == 0 ? [0x47, 0x40, 0x00, 0x10, 0x00, 0x00, 0xB0, 0x0D] : [0x47, 0x1F, 0xFF, 0x10]
            for (offset, byte) in header.enumerated() { packet[syncOffset + offset] = byte }
            for offset in 0..<syncOffset { packet[offset] = 0x00 }  // M2TS timecode
            bytes += packet
        }
        return bytes
    }

    // MARK: Text

    @Test func typeScriptSourceIsUTF8Text() throws {
        let source = "export const greet = <T,>(name: T): string => `Hi ${name}`;\n"
        let preview = try #require(text(classify(Array(source.utf8))))
        #expect(preview == TextPreview(text: source, encoding: .utf8, isTruncated: false))
    }

    @Test func emptyFileIsEmptyText() throws {
        let preview = try #require(text(classify([])))
        #expect(preview.text.isEmpty)
    }

    @Test func utf8ByteOrderMarkIsDropped() throws {
        let preview = try #require(text(classify([0xEF, 0xBB, 0xBF] + Array("let ñ = 1".utf8))))
        #expect(preview.text == "let ñ = 1")
        #expect(preview.encoding == .utf8)
    }

    @Test(arguments: [
        (String.Encoding.utf16LittleEndian, [UInt8]([0xFF, 0xFE])),
        (String.Encoding.utf16BigEndian, [UInt8]([0xFE, 0xFF])),
        (String.Encoding.utf32LittleEndian, [UInt8]([0xFF, 0xFE, 0x00, 0x00])),
    ])
    func byteOrderMarkSelectsEncoding(encoding: String.Encoding, bom: [UInt8]) throws {
        let source = "const π = 3.14 // 😀\n"
        let body = try #require(source.data(using: encoding))
        let preview = try #require(text(classify(bom + Array(body))))
        #expect(preview.text == source)
        #expect(preview.encoding == encoding)
    }

    @Test func invalidUTF8FallsBackToWindows1252() throws {
        // "café €5" in Windows-1252: é = 0xE9, € = 0x80.
        let preview = try #require(text(classify([0x63, 0x61, 0x66, 0xE9, 0x20, 0x80, 0x35])))
        #expect(preview.text == "café €5")
        #expect(preview.encoding == .windowsCP1252)
    }

    @Test func bytesUndefinedInWindows1252FallBackToLatin1() throws {
        let preview = try #require(text(classify([0x61, 0x81, 0x62, 0xE9])))
        #expect(preview.encoding == .isoLatin1)
        #expect(preview.text == "a\u{81}bé")
    }

    @Test func textWithSyncBytesAtPacketBoundariesStaysText() throws {
        // 'G' (0x47) starting every 188-byte line, but no NUL: still text.
        let line = "G" + String(repeating: "x", count: 186) + "\n"
        let source = String(repeating: line, count: 6)
        let preview = try #require(text(classify(Array(source.utf8))))
        #expect(preview.text == source)
    }

    @Test func terminalEscapesAndTabsAreText() {
        let source = "\u{1B}[31mred\u{1B}[0m\tdone\r\n"
        #expect(text(classify(Array(source.utf8))) != nil)
    }

    // MARK: Video and binary

    @Test func mpegTransportStreamIsDetected() {
        #expect(classify(transportStream(packets: 8)) == .transportStream)
    }

    @Test func m2tsAndFECPacketSizesAreDetected() {
        #expect(classify(transportStream(packets: 5, packetSize: 192, syncOffset: 4)) == .transportStream)
        #expect(classify(transportStream(packets: 5, packetSize: 204)) == .transportStream)
    }

    @Test func streamStartingMidPacketIsDetected() {
        // Cut past the PAT: only null packets (0xFF stuffing, no NUL) remain.
        let stream = Array(transportStream(packets: 8).dropFirst(100))
        #expect(!stream.contains(0))
        #expect(classify(stream) == .transportStream)
    }

    @Test func streamStartingWithAUTF16ByteOrderMarkIsStillVideo() {
        var stream = Array(transportStream(packets: 8).dropFirst(186))  // starts on the PAT's last stuffing bytes
        stream[0] = 0xFF
        stream[1] = 0xFE
        #expect(classify(stream) == .transportStream)
    }

    @Test func tooFewPacketsAreNotATransportStream() {
        #expect(classify(transportStream(packets: 2)) == .binary)
    }

    @Test func nulBytesMeanBinary() {
        #expect(classify(Array("const a = 1;".utf8) + [0x00] + Array("rest".utf8)) == .binary)
    }

    @Test func manyControlCharactersMeanBinary() {
        let bytes = (0..<200).map { UInt8(1 + $0 % 7) }  // 0x01...0x07, no NUL
        #expect(classify(bytes) == .binary)
    }

    // MARK: Truncation

    @Test func truncationInsideAUTF8CharacterKeepsUTF8() throws {
        // "aé" with the second byte of é cut off by the byte limit.
        let preview = try #require(text(classify([0x61, 0xC3], truncated: true)))
        #expect(preview == TextPreview(text: "a", encoding: .utf8, isTruncated: true))
    }

    @Test func truncationInsideAUTF16SurrogatePairDropsTheHalf() throws {
        let body = try #require("a😀".data(using: .utf16LittleEndian))  // 61 00 3D D8 00 DE
        let preview = try #require(text(classify([0xFF, 0xFE] + Array(body.prefix(5)), truncated: true)))
        #expect(preview.text == "a")
        #expect(preview.isTruncated)
    }

    @Test func completeUTF8PrefixIgnoresCompleteSequences() {
        #expect(TextPreviewDetection.completeUTF8Prefix(Array("aé😀".utf8)) == 7)
        #expect(TextPreviewDetection.completeUTF8Prefix([0x61, 0xF0, 0x9F, 0x98]) == 1)
        #expect(TextPreviewDetection.completeUTF8Prefix([0x80, 0x80]) == 2)
    }

    @Test func fileIsReadUpToTheByteLimit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextPreviewDetectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("app.ts")
        try Data("export {};\n".utf8).write(to: url)
        let exact = try #require(text(TextPreviewDetection.classify(contentsOf: url, byteLimit: 11)))
        #expect(exact == TextPreview(text: "export {};\n", encoding: .utf8, isTruncated: false))

        let cut = try #require(text(TextPreviewDetection.classify(contentsOf: url, byteLimit: 6)))
        #expect(cut == TextPreview(text: "export", encoding: .utf8, isTruncated: true))

        let video = directory.appendingPathComponent("clip.ts")
        try Data(transportStream(packets: 20)).write(to: video)
        #expect(try TextPreviewDetection.classify(contentsOf: video) == .transportStream)
    }

    // MARK: HTML

    @Test func htmlEscapesTheText() {
        let preview = TextPreview(text: "a < b && \"c\" > d", encoding: .utf8, isTruncated: false)
        let html = TextPreviewHTML.document(for: preview)
        #expect(html.contains("<pre>a &lt; b &amp;&amp; &quot;c&quot; &gt; d</pre>"))
        #expect(!html.contains("class=\"note\""))
    }

    @Test func htmlNotesTruncation() {
        let preview = TextPreview(text: String(repeating: "x", count: 2048), encoding: .utf8, isTruncated: true)
        let html = TextPreviewHTML.document(for: preview, totalByteCount: 5_000_000)
        #expect(html.contains("class=\"note\">Showing the first 2 KB of 5 MB."))
    }
}
