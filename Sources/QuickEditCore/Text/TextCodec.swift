import Foundation

/// Text decoded from file bytes, with the encoding needed to write it back.
public struct DecodedText: Sendable {
    public let text: String
    public let encoding: TextEncoding
    /// True when encoding `text` with `encoding` gives back exactly the original bytes. Files decoded lossily (or whose
    /// encoding doesn't round trip) must open read-only.
    public let isExact: Bool

    public init(text: String, encoding: TextEncoding, isExact: Bool) {
        self.text = text
        self.encoding = encoding
        self.isExact = isExact
    }
}

public enum TextCodecError: Error, Equatable {
    case binary
    case undecodable
    case unrepresentable(TextEncoding)
}

/// Byte-exact decoding and encoding of text files.
public enum TextCodec {
    /// How many leading bytes the binary and BOM-less UTF-16/32 heuristics look at.
    static let sampleSize = 8192

    /// True for files that aren't text: NUL bytes or many control bytes in the first 8 KB. UTF-16/32 text (with or
    /// without BOM) contains NUL bytes but is not binary.
    public static func isBinary(_ data: Data) -> Bool {
        if data.isEmpty || unicodeBOM(data) != nil { return false }
        let sample = data.prefix(sampleSize)
        if guessBOMlessUnicode(sample, isComplete: sample.count == data.count) != nil { return false }
        return hasBinaryBytes(sample)
    }

    /// NUL bytes, or more than 30% control bytes other than whitespace and escape.
    static func hasBinaryBytes(_ sample: Data) -> Bool {
        var controls = 0
        for byte in sample {
            switch byte {
            case 0x00: return true
            case 0x01...0x08, 0x0E...0x1A, 0x1C...0x1F: controls += 1
            default: break
            }
        }
        return controls * 10 > sample.count * 3
    }

    /// Detects the encoding: a BOM (UTF-8/16/32), then BOM-less UTF-32/16, then valid UTF-8, then Foundation's
    /// detection for legacy encodings (mostly-valid UTF-8 with stray bytes stays lossy UTF-8). Throws `.binary` for
    /// binary data. Never throws `.undecodable`: data that no encoding reads exactly comes back lossily decoded with
    /// `isExact == false`.
    public static func decode(_ data: Data) throws -> DecodedText {
        if data.isEmpty { return DecodedText(text: "", encoding: .utf8, isExact: true) }
        if let encoding = unicodeBOM(data) {
            return decodeUnicode(data, as: encoding.encoding)
        }
        let sample = data.prefix(sampleSize)
        // Before UTF-8: ASCII-heavy UTF-16/32 is full of NUL bytes, which are valid UTF-8.
        if let encoding = guessBOMlessUnicode(sample, isComplete: sample.count == data.count) {
            return decodeUnicode(data, as: encoding)
        }
        if hasBinaryBytes(sample) { throw TextCodecError.binary }
        if let text = String(validating: data, as: UTF8.self) {
            return DecodedText(text: text, encoding: .utf8, isExact: true)
        }
        if looksLikeDamagedUTF8(data) {
            return DecodedText(text: String(decoding: data, as: UTF8.self), encoding: .utf8, isExact: false)
        }
        if let detected = detectLegacy(data) { return detected }
        return DecodedText(text: String(decoding: data, as: UTF8.self), encoding: .utf8, isExact: false)
    }

    /// Decodes with a chosen encoding ("Reopen with Encoding"). For Unicode encodings a matching BOM is skipped and
    /// reported through `encoding.hasBOM`; invalid sequences become U+FFFD with `isExact == false`. Legacy encodings
    /// that can't read the bytes at all throw `.undecodable`.
    public static func decode(_ data: Data, as encoding: TextEncoding) throws -> DecodedText {
        if encoding.isUnicode { return decodeUnicode(data, as: encoding.encoding) }
        if let text = String(data: data, encoding: encoding.encoding) {
            return DecodedText(text: text, encoding: encoding, isExact: roundTrips(text, encoding, data))
        }
        var converted: NSString?
        var lossy: ObjCBool = false
        let options: [StringEncodingDetectionOptionsKey: Any] = [
            .suggestedEncodingsKey: [NSNumber(value: encoding.encoding.rawValue)],
            .useOnlySuggestedEncodingsKey: true,
            .allowLossyKey: true,
        ]
        let raw = NSString.stringEncoding(
            for: data, encodingOptions: options, convertedString: &converted, usedLossyConversion: &lossy)
        guard raw == encoding.encoding.rawValue, let converted else { throw TextCodecError.undecodable }
        return DecodedText(text: converted as String, encoding: encoding, isExact: false)
    }

    /// Encodes `text`, writing the BOM when `encoding.hasBOM`. Throws `.unrepresentable` when a legacy encoding can't
    /// hold every character.
    public static func encode(_ text: String, as encoding: TextEncoding) throws -> Data {
        var bytes = encoding.bom
        switch encoding.encoding {
        case .utf8:
            bytes.append(contentsOf: text.utf8)
        case .utf16LittleEndian, .utf16BigEndian:
            let bigEndian = encoding.encoding == .utf16BigEndian
            bytes.reserveCapacity(bytes.count + text.utf16.count * 2)
            for unit in text.utf16 {
                let value = bigEndian ? unit.bigEndian : unit.littleEndian
                withUnsafeBytes(of: value) { bytes.append(contentsOf: $0) }
            }
        case .utf32LittleEndian, .utf32BigEndian:
            let bigEndian = encoding.encoding == .utf32BigEndian
            bytes.reserveCapacity(bytes.count + text.unicodeScalars.count * 4)
            for scalar in text.unicodeScalars {
                let value = bigEndian ? scalar.value.bigEndian : scalar.value.littleEndian
                withUnsafeBytes(of: value) { bytes.append(contentsOf: $0) }
            }
        default:
            if text.isEmpty { return Data() }
            guard let data = text.data(using: encoding.encoding, allowLossyConversion: false) else {
                throw TextCodecError.unrepresentable(encoding)
            }
            return data
        }
        return Data(bytes)
    }

    // MARK: - Unicode

    /// The encoding announced by a leading BOM. A UTF-32 LE BOM wins over UTF-16 LE only when the length allows it.
    static func unicodeBOM(_ data: Data) -> TextEncoding? {
        let head = Array(data.prefix(4))
        if head.starts(with: [0xEF, 0xBB, 0xBF]) { return .utf8WithBOM }
        if head == [0x00, 0x00, 0xFE, 0xFF], data.count % 4 == 0 { return .utf32BigEndian }
        if head == [0xFF, 0xFE, 0x00, 0x00], data.count % 4 == 0 { return .utf32LittleEndian }
        if head.starts(with: [0xFE, 0xFF]) { return .utf16BigEndian }
        if head.starts(with: [0xFF, 0xFE]) { return .utf16LittleEndian }
        return nil
    }

    /// Decodes UTF-8/16/32, skipping this encoding's BOM when present. Invalid input decodes with replacement
    /// characters and `isExact == false`.
    static func decodeUnicode(_ data: Data, as encoding: String.Encoding) -> DecodedText {
        let bom = TextEncoding.bom(for: encoding)
        let hasBOM = data.starts(with: bom)
        let body = hasBOM ? data.dropFirst(bom.count) : data[...]
        let result = TextEncoding(encoding, hasBOM: hasBOM)
        switch encoding {
        case .utf8:
            if let text = String(validating: body, as: UTF8.self) {
                return DecodedText(text: text, encoding: result, isExact: true)
            }
            return DecodedText(text: String(decoding: body, as: UTF8.self), encoding: result, isExact: false)
        case .utf16LittleEndian, .utf16BigEndian:
            let units = codeUnits16(body, bigEndian: encoding == .utf16BigEndian)
            if body.count % 2 == 0, let text = String(validating: units, as: UTF16.self) {
                return DecodedText(text: text, encoding: result, isExact: true)
            }
            var text = String(decoding: units, as: UTF16.self)
            if body.count % 2 != 0 { text.append("\u{FFFD}") }
            return DecodedText(text: text, encoding: result, isExact: false)
        default:
            let units = codeUnits32(body, bigEndian: encoding == .utf32BigEndian)
            if body.count % 4 == 0, let text = String(validating: units, as: UTF32.self) {
                return DecodedText(text: text, encoding: result, isExact: true)
            }
            var text = String(decoding: units, as: UTF32.self)
            if body.count % 4 != 0 { text.append("\u{FFFD}") }
            return DecodedText(text: text, encoding: result, isExact: false)
        }
    }

    static func codeUnits16(_ bytes: Data.SubSequence, bigEndian: Bool) -> [UInt16] {
        bytes.withUnsafeBytes { raw in
            let count = raw.count / 2
            return [UInt16](unsafeUninitializedCapacity: count) { buffer, initialized in
                for index in 0..<count {
                    let first = UInt16(raw[index * 2]), second = UInt16(raw[index * 2 + 1])
                    buffer[index] = bigEndian ? first << 8 | second : second << 8 | first
                }
                initialized = count
            }
        }
    }

    static func codeUnits32(_ bytes: Data.SubSequence, bigEndian: Bool) -> [UInt32] {
        bytes.withUnsafeBytes { raw in
            let count = raw.count / 4
            return [UInt32](unsafeUninitializedCapacity: count) { buffer, initialized in
                for index in 0..<count {
                    var value: UInt32 = 0
                    for offset in 0..<4 {
                        let byte = UInt32(raw[index * 4 + (bigEndian ? offset : 3 - offset)])
                        value = value << 8 | byte
                    }
                    buffer[index] = value
                }
                initialized = count
            }
        }
    }

    /// Recognizes BOM-less UTF-32 and UTF-16 by their shape: every unit a valid, non-NUL scalar, no C0 controls other
    /// than whitespace and escape, and (for UTF-16) zero bytes almost only on one side of each unit.
    /// `isComplete` says the sample is the whole file, so a trailing partial unit means it isn't this encoding.
    static func guessBOMlessUnicode(_ sample: Data, isComplete: Bool) -> String.Encoding? {
        guard sample.count >= 4 else { return nil }
        for bigEndian in [false, true] where !isComplete || sample.count % 4 == 0 {
            let units = codeUnits32(sample[...], bigEndian: bigEndian)
            if units.allSatisfy({ isPlausibleText($0) && $0 <= 0x10FFFF && !(0xD800...0xDFFF).contains($0) }) {
                return bigEndian ? .utf32BigEndian : .utf32LittleEndian
            }
        }
        guard !isComplete || sample.count % 2 == 0 else { return nil }
        var zerosAtEven = 0, zerosAtOdd = 0
        for (offset, byte) in sample.enumerated() where byte == 0 {
            if offset % 2 == 0 { zerosAtEven += 1 } else { zerosAtOdd += 1 }
        }
        // ASCII-range characters put their zero byte on one side. Normally a quarter of the units are like that;
        // CJK-heavy text may have only a few, which is enough when the bytes aren't UTF-8 (8-bit text with a stray
        // NUL is valid UTF-8, CJK in UTF-16 practically never is).
        let unitCount = sample.count / 2
        let bigEndian: Bool
        func predominant(_ zeros: Int, over other: Int) -> Bool {
            zeros > 0 && other * 10 <= zeros
                && (zeros * 4 >= unitCount || !isValidUTF8Prefix(sample, isComplete: isComplete))
        }
        if predominant(zerosAtOdd, over: zerosAtEven) {
            bigEndian = false
        } else if predominant(zerosAtEven, over: zerosAtOdd) {
            bigEndian = true
        } else {
            return nil
        }
        let units = codeUnits16(sample[...], bigEndian: bigEndian)
        guard units.allSatisfy({ isPlausibleText(UInt32($0)) }) else { return nil }
        // Validate surrogate pairing, tolerating a pair cut by the end of the sample.
        var index = 0
        while index < units.count {
            let unit = units[index]
            if UTF16.isLeadSurrogate(unit) {
                if index + 1 == units.count { break }
                guard UTF16.isTrailSurrogate(units[index + 1]) else { return nil }
                index += 2
            } else if UTF16.isTrailSurrogate(unit) {
                return nil
            } else {
                index += 1
            }
        }
        return bigEndian ? .utf16BigEndian : .utf16LittleEndian
    }

    /// Valid UTF-8, allowing a sequence cut by the end of a partial sample.
    private static func isValidUTF8Prefix(_ sample: Data, isComplete: Bool) -> Bool {
        for trimmed in 0...(isComplete ? 0 : 3) where String(validating: sample.dropLast(trimmed), as: UTF8.self) != nil {
            return true
        }
        return false
    }

    private static func isPlausibleText(_ value: UInt32) -> Bool {
        switch value {
        case 0x09, 0x0A, 0x0C, 0x0D, 0x1B: true
        case 0x00..<0x20: false
        default: true
        }
    }

    /// Mostly-valid UTF-8 with a few stray bytes reads better as lossy UTF-8 than as a legacy encoding guess.
    static func looksLikeDamagedUTF8(_ data: Data) -> Bool {
        var valid = 0, invalid = 0
        var iterator = data.makeIterator()
        var decoder = UTF8()
        loop: while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar): if scalar.value >= 0x80 { valid += 1 }
            case .error: invalid += 1
            case .emptyInput: break loop
            }
        }
        return valid > invalid
    }

    /// Foundation's detection for legacy (non-Unicode) encodings, checked for an exact round trip.
    static func detectLegacy(_ data: Data) -> DecodedText? {
        var converted: NSString?
        var lossy: ObjCBool = false
        let options: [StringEncodingDetectionOptionsKey: Any] = [
            .suggestedEncodingsKey: [NSNumber(value: String.Encoding.windowsCP1252.rawValue)],
            .allowLossyKey: false,
        ]
        let raw = NSString.stringEncoding(
            for: data, encodingOptions: options, convertedString: &converted, usedLossyConversion: &lossy)
        guard raw != 0, let converted else { return nil }
        let detected = String.Encoding(rawValue: raw)
        let encoding: TextEncoding = switch detected {
        case .utf16, .utf16BigEndian: TextEncoding(.utf16BigEndian)
        case .utf32, .utf32BigEndian: TextEncoding(.utf32BigEndian)
        default: TextEncoding(detected)
        }
        let text = converted as String
        let exact = !lossy.boolValue && roundTrips(text, encoding, data)
        return DecodedText(text: text, encoding: encoding, isExact: exact)
    }

    static func roundTrips(_ text: String, _ encoding: TextEncoding, _ data: Data) -> Bool {
        (try? encode(text, as: encoding)) == data
    }
}
