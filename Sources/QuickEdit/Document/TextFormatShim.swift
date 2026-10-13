import Foundation

// TEMPORARY: minimal stand-ins for the QuickEditCore text-format API (TASK-3, being written in parallel).
// Same names and signatures, so deleting this file switches the app to the Core implementation.

nonisolated enum LineEnding: String, CaseIterable, Sendable {
    case lf = "\n", crlf = "\r\n", cr = "\r"

    var displayName: String {
        switch self {
        case .lf: "LF"
        case .crlf: "CRLF"
        case .cr: "CR"
        }
    }
}

nonisolated struct LineEndingInfo: Equatable, Sendable {
    let dominant: LineEnding
    let isMixed: Bool
    let counts: [LineEnding: Int]
}

nonisolated enum LineEndings {
    static func detect(_ text: String) -> LineEndingInfo {
        var counts: [LineEnding: Int] = [:]
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            if units[index] == 13 {
                if index + 1 < units.count, units[index + 1] == 10 {
                    counts[.crlf, default: 0] += 1
                    index += 1
                } else {
                    counts[.cr, default: 0] += 1
                }
            } else if units[index] == 10 {
                counts[.lf, default: 0] += 1
            }
            index += 1
        }
        let dominant = counts.max { $0.value < $1.value }?.key ?? .lf
        return LineEndingInfo(dominant: dominant, isMixed: counts.count > 1, counts: counts)
    }

    static func convert(_ text: String, to ending: LineEnding) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: ending.rawValue)
    }
}

nonisolated struct TextEncoding: Hashable, Sendable {
    let encoding: String.Encoding
    let hasBOM: Bool

    var displayName: String {
        hasBOM ? "\(String.localizedName(of: encoding)) with BOM" : String.localizedName(of: encoding)
    }

    static let utf8 = TextEncoding(encoding: .utf8, hasBOM: false)
    static let common: [TextEncoding] = [
        .utf8, TextEncoding(encoding: .utf8, hasBOM: true),
        TextEncoding(encoding: .utf16LittleEndian, hasBOM: true), TextEncoding(encoding: .utf16BigEndian, hasBOM: true),
        TextEncoding(encoding: .windowsCP1252, hasBOM: false), TextEncoding(encoding: .isoLatin1, hasBOM: false),
        TextEncoding(encoding: .macOSRoman, hasBOM: false),
    ]
}

nonisolated struct DecodedText: Sendable {
    let text: String
    let encoding: TextEncoding
    let isExact: Bool
}

nonisolated enum TextCodecError: Error, Equatable {
    case binary, undecodable, unrepresentable(TextEncoding)
}

nonisolated enum TextCodec {
    static func isBinary(_ data: Data) -> Bool {
        data.prefix(8000).contains(0)
    }

    static func decode(_ data: Data) throws -> DecodedText {
        if isBinary(data) { throw TextCodecError.binary }
        if let text = String(data: data, encoding: .utf8) { return DecodedText(text: text, encoding: .utf8, isExact: true) }
        var converted: NSString?
        var lossy: ObjCBool = false
        let raw = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: &lossy)
        guard let converted, raw != 0 else { throw TextCodecError.undecodable }
        return DecodedText(text: converted as String, encoding: TextEncoding(encoding: String.Encoding(rawValue: raw), hasBOM: false), isExact: !lossy.boolValue)
    }

    static func decode(_ data: Data, as encoding: TextEncoding) throws -> DecodedText {
        guard let text = String(data: data, encoding: encoding.encoding) else { throw TextCodecError.undecodable }
        return DecodedText(text: text, encoding: encoding, isExact: true)
    }

    static func encode(_ text: String, as encoding: TextEncoding) throws -> Data {
        guard let data = text.data(using: encoding.encoding) else { throw TextCodecError.unrepresentable(encoding) }
        return data
    }
}

nonisolated enum IndentStyle: String, Sendable {
    case tabs, spaces
}

nonisolated struct Indentation: Equatable, Sendable {
    var style: IndentStyle
    var width: Int

    var unit: String { style == .tabs ? "\t" : String(repeating: " ", count: max(1, width)) }
}

nonisolated enum IndentationDetector {
    static func detect(_ text: String) -> Indentation? {
        var tabs = 0
        var spaces = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(2000) {
            if line.hasPrefix("\t") { tabs += 1 } else if line.hasPrefix("  ") { spaces += 1 }
        }
        if tabs == 0 && spaces == 0 { return nil }
        return tabs > spaces ? Indentation(style: .tabs, width: 4) : Indentation(style: .spaces, width: 4)
    }

    static func convert(_ text: String, from: Indentation, to: Indentation) -> String {
        text
    }
}

nonisolated enum RiskyCharacters {
    static func count(in text: NSString) -> Int { 0 }
}
