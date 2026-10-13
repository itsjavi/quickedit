import Foundation
import QuickEditCore
import Testing

/// Decodes `bytes` and checks that encoding the text again reproduces them exactly.
@discardableResult
private func expectExactRoundTrip(
    _ bytes: [UInt8], as expected: TextEncoding, sourceLocation: SourceLocation = #_sourceLocation
) throws -> DecodedText {
    let data = Data(bytes)
    let decoded = try TextCodec.decode(data)
    #expect(decoded.encoding == expected, sourceLocation: sourceLocation)
    #expect(decoded.isExact, sourceLocation: sourceLocation)
    #expect(try TextCodec.encode(decoded.text, as: decoded.encoding) == data, sourceLocation: sourceLocation)
    return decoded
}

private let sample = "Héllo, wörld 😀 日本\r\nsecond\rthird\nfourth\r\n"

private func utf16(_ text: String, bigEndian: Bool, bom: Bool) -> [UInt8] {
    var bytes: [UInt8] = bom ? (bigEndian ? [0xFE, 0xFF] : [0xFF, 0xFE]) : []
    for unit in text.utf16 {
        let (high, low) = (UInt8(unit >> 8), UInt8(unit & 0xFF))
        bytes += bigEndian ? [high, low] : [low, high]
    }
    return bytes
}

private func utf32(_ text: String, bigEndian: Bool, bom: Bool) -> [UInt8] {
    var bytes: [UInt8] = bom ? (bigEndian ? [0, 0, 0xFE, 0xFF] : [0xFF, 0xFE, 0, 0]) : []
    for scalar in text.unicodeScalars {
        let value = scalar.value
        let le = [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24)]
        bytes += bigEndian ? le.reversed() : le
    }
    return bytes
}

@Suite struct TextCodecRoundTripTests {
    @Test func utf8() throws {
        let decoded = try expectExactRoundTrip(Array(sample.utf8), as: .utf8)
        #expect(decoded.text == sample)
    }

    @Test func utf8KeepsDecomposedCharacters() throws {
        // NFD "é" must not be normalized to NFC on the way through.
        let decoded = try expectExactRoundTrip(Array("e\u{301}\n".utf8), as: .utf8)
        #expect(decoded.text.unicodeScalars.count == 3)
    }

    @Test func utf8WithBOM() throws {
        let decoded = try expectExactRoundTrip([0xEF, 0xBB, 0xBF] + Array(sample.utf8), as: .utf8WithBOM)
        #expect(decoded.text == sample)
        #expect(decoded.text.unicodeScalars.first != "\u{FEFF}")
    }

    @Test func utf16WithBOM() throws {
        let le = try expectExactRoundTrip(utf16(sample, bigEndian: false, bom: true), as: .utf16LittleEndian)
        #expect(le.text == sample)
        let be = try expectExactRoundTrip(utf16(sample, bigEndian: true, bom: true), as: .utf16BigEndian)
        #expect(be.text == sample)
    }

    @Test func utf32WithBOM() throws {
        let le = try expectExactRoundTrip(utf32(sample, bigEndian: false, bom: true), as: .utf32LittleEndian)
        #expect(le.text == sample)
        let be = try expectExactRoundTrip(utf32(sample, bigEndian: true, bom: true), as: .utf32BigEndian)
        #expect(be.text == sample)
    }

    @Test func utf16WithoutBOM() throws {
        let text = "plain ASCII heavy text, with a ü and 😀\r\nline two\n"
        let le = try expectExactRoundTrip(utf16(text, bigEndian: false, bom: false), as: TextEncoding(.utf16LittleEndian))
        #expect(le.text == text)
        let be = try expectExactRoundTrip(utf16(text, bigEndian: true, bom: false), as: TextEncoding(.utf16BigEndian))
        #expect(be.text == text)
    }

    @Test func cjkHeavyUTF16WithoutBOM() throws {
        let text = "日本語のテキストです。中文文本。한국어 텍스트\r\n"
        let le = try expectExactRoundTrip(utf16(text, bigEndian: false, bom: false), as: TextEncoding(.utf16LittleEndian))
        #expect(le.text == text)
        let be = try expectExactRoundTrip(utf16(text, bigEndian: true, bom: false), as: TextEncoding(.utf16BigEndian))
        #expect(be.text == text)
    }

    @Test func utf32WithoutBOM() throws {
        let text = "utf-32 text 😀\n"
        let le = try expectExactRoundTrip(utf32(text, bigEndian: false, bom: false), as: TextEncoding(.utf32LittleEndian))
        #expect(le.text == text)
        let be = try expectExactRoundTrip(utf32(text, bigEndian: true, bom: false), as: TextEncoding(.utf32BigEndian))
        #expect(be.text == text)
    }

    @Test func windows1252IsDetected() throws {
        // "café € “quoted”" with Windows-1252 bytes for é, €, “ and ”.
        let bytes: [UInt8] = Array("caf".utf8) + [0xE9, 0x20, 0x80, 0x20, 0x93] + Array("quoted".utf8) + [0x94, 0x0D, 0x0A]
        let decoded = try expectExactRoundTrip(bytes, as: .windowsLatin1)
        #expect(decoded.text == "café € “quoted”\r\n")
    }

    @Test func latin1EveryByte() throws {
        let bytes: [UInt8] = [0x09, 0x0A, 0x0D] + Array(0x20...0xFF)
        let decoded = try TextCodec.decode(Data(bytes), as: .isoLatin1)
        #expect(decoded.isExact)
        #expect(decoded.text.unicodeScalars.map(\.value) == bytes.map(UInt32.init))
        #expect(try TextCodec.encode(decoded.text, as: .isoLatin1) == Data(bytes))
    }

    @Test func legacyEncodingsChosenExplicitly() throws {
        let cases: [(String, TextEncoding)] = [
            ("Ça coûte 5 €\r\n", .macRoman),
            ("Ça coûte 5 €\r\n", .windowsLatin1),
            ("日本語のテキスト\n", TextEncoding(.shiftJIS)),
            ("日本語のテキスト\n", TextEncoding(.japaneseEUC)),
            ("Привет, мир\r", TextEncoding(.windowsCP1251)),
        ]
        for (text, encoding) in cases {
            let data = try TextCodec.encode(text, as: encoding)
            let decoded = try TextCodec.decode(data, as: encoding)
            #expect(decoded.text == text, "\(encoding.displayName)")
            #expect(decoded.isExact, "\(encoding.displayName)")
            #expect(try TextCodec.encode(decoded.text, as: encoding) == data, "\(encoding.displayName)")
        }
    }

    @Test func detectedLegacyEncodingRoundTrips() throws {
        let data = try TextCodec.encode("日本語のテキストです。こんにちは世界\n", as: TextEncoding(.shiftJIS))
        let decoded = try TextCodec.decode(data)
        #expect(decoded.isExact)
        #expect(try TextCodec.encode(decoded.text, as: decoded.encoding) == data)
    }

    @Test func everyCommonEncodingRoundTripsASCII() throws {
        let text = "Hello, world!\r\n\tindented\rmixed\n"
        for encoding in TextEncoding.common {
            let data = try TextCodec.encode(text, as: encoding)
            let decoded = try TextCodec.decode(data, as: encoding)
            #expect(decoded.text == text, "\(encoding.displayName)")
            #expect(decoded.encoding == encoding, "\(encoding.displayName)")
            #expect(decoded.isExact, "\(encoding.displayName)")
            #expect(try TextCodec.encode(decoded.text, as: encoding) == data, "\(encoding.displayName)")
        }
    }

    @Test func lineEndingsSurviveInEveryUnicodeForm() throws {
        let text = "a\r\nb\rc\nd\r\n\r\r\n"
        for encoding in [TextEncoding.utf8, .utf8WithBOM, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
            let data = try TextCodec.encode(text, as: encoding)
            let decoded = try TextCodec.decode(data)
            #expect(decoded.encoding == encoding)
            #expect(Array(decoded.text.utf8) == Array(text.utf8))
            #expect(try TextCodec.encode(decoded.text, as: decoded.encoding) == data)
        }
    }
}

@Suite struct TextCodecDetectionTests {
    @Test func emptyDataIsUTF8() throws {
        let decoded = try TextCodec.decode(Data())
        #expect(decoded.text.isEmpty)
        #expect(decoded.encoding == .utf8)
        #expect(decoded.isExact)
    }

    @Test func binaryData() {
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52]
        #expect(TextCodec.isBinary(Data(png)))
        #expect(throws: TextCodecError.binary) { try TextCodec.decode(Data(png)) }
        #expect(TextCodec.isBinary(Data("text with a\0NUL byte".utf8)))
        #expect(TextCodec.isBinary(Data((0..<200).map { UInt8($0 % 8 + 1) })))  // mostly control bytes
    }

    @Test func textIsNotBinary() {
        #expect(!TextCodec.isBinary(Data()))
        #expect(!TextCodec.isBinary(Data(sample.utf8)))
        #expect(!TextCodec.isBinary(Data("\u{1B}[31mred\u{1B}[0m log line\n".utf8)))
        #expect(!TextCodec.isBinary(Data(utf16(sample, bigEndian: false, bom: true))))
        #expect(!TextCodec.isBinary(Data(utf16("ascii text\n", bigEndian: false, bom: false))))
        #expect(!TextCodec.isBinary(Data(utf16("ascii text\n", bigEndian: true, bom: false))))
        #expect(!TextCodec.isBinary(Data(utf32("ascii text\n", bigEndian: false, bom: false))))
    }

    @Test func lossyDecodingIsNotExact() throws {
        let invalid: [UInt8] = Array("abc".utf8) + [0xC3, 0x28] + Array("def".utf8)
        let decoded = try TextCodec.decode(Data(invalid), as: .utf8)
        #expect(!decoded.isExact)
        #expect(decoded.text.contains("\u{FFFD}"))
        #expect(try TextCodec.encode(decoded.text, as: decoded.encoding) != Data(invalid))
    }

    @Test func mostlyUTF8WithStrayByteStaysLossyUTF8() throws {
        let bytes: [UInt8] = Array("héllo wörld, ünïcödé\n".utf8) + [0xE9] + Array(" more\n".utf8)
        let decoded = try TextCodec.decode(Data(bytes))
        #expect(decoded.encoding == .utf8)
        #expect(!decoded.isExact)
        #expect(decoded.text.hasPrefix("héllo wörld"))
    }

    @Test func invalidUTF16IsNotExact() throws {
        // BOM, "A", then a lone high surrogate.
        let loneSurrogate: [UInt8] = [0xFF, 0xFE, 0x41, 0x00, 0x3D, 0xD8, 0x42, 0x00]
        let decoded = try TextCodec.decode(Data(loneSurrogate))
        #expect(decoded.encoding == .utf16LittleEndian)
        #expect(!decoded.isExact)
        // Odd length.
        let odd = try TextCodec.decode(Data([0x41, 0x00, 0x42]), as: .utf16LittleEndian)
        #expect(!odd.isExact)
        #expect(odd.text == "A\u{FFFD}")
    }

    @Test func legacyBytesThatDontFitAreNotExact() throws {
        // 0x81 is undefined in Windows-1252.
        let data = Data([0x41, 0x81, 0x42])
        do {
            let decoded = try TextCodec.decode(data, as: .windowsLatin1)
            #expect(!decoded.isExact)
        } catch {
            #expect(error as? TextCodecError == .undecodable)
        }
        // Automatic detection never claims an exact decoding that doesn't round trip.
        let detected = try TextCodec.decode(data)
        #expect(detected.isExact == ((try? TextCodec.encode(detected.text, as: detected.encoding)) == data))
    }

    @Test func reopenReportsTheActualBOM() throws {
        let withBOM = try TextCodec.decode(Data([0xEF, 0xBB, 0xBF, 0x41]), as: .utf8)
        #expect(withBOM.encoding == .utf8WithBOM)
        #expect(withBOM.text == "A")
        #expect(withBOM.isExact)
        let withoutBOM = try TextCodec.decode(Data([0x41]), as: .utf8WithBOM)
        #expect(withoutBOM.encoding == .utf8)
        #expect(withoutBOM.isExact)
    }

    @Test func reopenUTF8FileAsLatin1() throws {
        let data = Data("café".utf8)
        let decoded = try TextCodec.decode(data, as: .isoLatin1)
        #expect(decoded.text == "cafÃ©")
        #expect(decoded.isExact)
    }
}

@Suite struct TextCodecEncodingTests {
    @Test func writesTheBOM() throws {
        #expect(try TextCodec.encode("A", as: .utf8WithBOM) == Data([0xEF, 0xBB, 0xBF, 0x41]))
        #expect(try TextCodec.encode("A", as: .utf16BigEndian) == Data([0xFE, 0xFF, 0x00, 0x41]))
        #expect(try TextCodec.encode("A", as: .utf16LittleEndian) == Data([0xFF, 0xFE, 0x41, 0x00]))
        #expect(try TextCodec.encode("A", as: .utf32BigEndian) == Data([0, 0, 0xFE, 0xFF, 0, 0, 0, 0x41]))
        #expect(try TextCodec.encode("A", as: TextEncoding(.utf16LittleEndian)) == Data([0x41, 0x00]))
        #expect(try TextCodec.encode("", as: .utf8WithBOM) == Data([0xEF, 0xBB, 0xBF]))
    }

    @Test func unrepresentableCharactersThrow() {
        #expect(throws: TextCodecError.unrepresentable(.isoLatin1)) { try TextCodec.encode("5 €", as: .isoLatin1) }
        #expect(throws: TextCodecError.unrepresentable(.windowsLatin1)) { try TextCodec.encode("日本", as: .windowsLatin1) }
        #expect(throws: TextCodecError.unrepresentable(.macRoman)) { try TextCodec.encode("😀", as: .macRoman) }
    }

    @Test func encodingNormalization() {
        #expect(TextEncoding(.utf16, hasBOM: true) == .utf16LittleEndian)
        #expect(TextEncoding(.utf32, hasBOM: true) == .utf32LittleEndian)
        #expect(!TextEncoding(.windowsCP1252, hasBOM: true).hasBOM)
        #expect(TextEncoding.utf8.isUnicode)
        #expect(!TextEncoding.windowsLatin1.isUnicode)
    }

    @Test func displayNames() {
        #expect(TextEncoding.utf8.displayName == "UTF-8")
        #expect(TextEncoding.utf8WithBOM.displayName == "UTF-8 with BOM")
        #expect(TextEncoding.utf16LittleEndian.displayName == "UTF-16 LE")
        #expect(TextEncoding(.utf16BigEndian).displayName == "UTF-16 BE without BOM")
        #expect(TextEncoding.windowsLatin1.displayName == "Windows Latin 1")
        #expect(TextEncoding.isoLatin1.displayName == "ISO Latin 1")
        #expect(TextEncoding.macRoman.displayName == "Mac Roman")
    }

    @Test func commonEncodingsAreUniqueAndNamed() {
        let common = TextEncoding.common
        #expect(common.first == .utf8)
        #expect(Set(common).count == common.count)
        #expect(Set(common.map(\.displayName)).count == common.count)
        #expect(common.allSatisfy { !$0.displayName.isEmpty })
    }
}
