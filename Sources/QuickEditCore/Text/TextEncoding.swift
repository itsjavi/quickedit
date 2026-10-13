import Foundation

/// A text encoding plus whether the file starts with a byte order mark.
///
/// UTF-16 and UTF-32 are always stored with an explicit byte order (`.utf16` and `.utf32` normalize to little endian),
/// so the BOM is a separate fact instead of being implied by the encoding. Non-Unicode encodings never have a BOM.
public struct TextEncoding: Hashable, Sendable {
    public let encoding: String.Encoding
    public let hasBOM: Bool

    public init(_ encoding: String.Encoding, hasBOM: Bool = false) {
        let normalized: String.Encoding = switch encoding {
        case .utf16: .utf16LittleEndian
        case .utf32: .utf32LittleEndian
        default: encoding
        }
        self.encoding = normalized
        self.hasBOM = Self.unicodeEncodings.contains(normalized) && hasBOM
    }

    public static let utf8 = TextEncoding(.utf8)
    public static let utf8WithBOM = TextEncoding(.utf8, hasBOM: true)
    public static let utf16LittleEndian = TextEncoding(.utf16LittleEndian, hasBOM: true)
    public static let utf16BigEndian = TextEncoding(.utf16BigEndian, hasBOM: true)
    public static let utf32LittleEndian = TextEncoding(.utf32LittleEndian, hasBOM: true)
    public static let utf32BigEndian = TextEncoding(.utf32BigEndian, hasBOM: true)
    public static let windowsLatin1 = TextEncoding(.windowsCP1252)
    public static let isoLatin1 = TextEncoding(.isoLatin1)
    public static let macRoman = TextEncoding(.macOSRoman)

    /// The encodings offered by the status bar menu, Unicode first.
    public static let common: [TextEncoding] = [
        .utf8, .utf8WithBOM,
        .utf16LittleEndian, .utf16BigEndian,
        .utf32LittleEndian, .utf32BigEndian,
        .windowsLatin1, .isoLatin1, .macRoman,
        TextEncoding(.windowsCP1250), TextEncoding(.isoLatin2),
        TextEncoding(.windowsCP1251), TextEncoding(cf: 0x0A02 /* KOI8-R */),
        TextEncoding(.windowsCP1253), TextEncoding(.windowsCP1254),
        TextEncoding(.shiftJIS), TextEncoding(.japaneseEUC), TextEncoding(.iso2022JP),
        TextEncoding(cf: 0x0632 /* GB 18030 */), TextEncoding(cf: 0x0A03 /* Big 5 */),
        TextEncoding(cf: 0x0940 /* EUC-KR */),
    ]

    /// True for UTF-8, UTF-16 and UTF-32: every Swift string is representable.
    public var isUnicode: Bool { Self.unicodeEncodings.contains(encoding) }

    /// The byte order mark written before the text when `hasBOM` is set (empty otherwise).
    public var bom: [UInt8] {
        guard hasBOM else { return [] }
        return Self.bom(for: encoding)
    }

    public var displayName: String {
        switch encoding {
        case .utf8: return hasBOM ? "UTF-8 with BOM" : "UTF-8"
        case .utf16LittleEndian: return hasBOM ? "UTF-16 LE" : "UTF-16 LE without BOM"
        case .utf16BigEndian: return hasBOM ? "UTF-16 BE" : "UTF-16 BE without BOM"
        case .utf32LittleEndian: return hasBOM ? "UTF-32 LE" : "UTF-32 LE without BOM"
        case .utf32BigEndian: return hasBOM ? "UTF-32 BE" : "UTF-32 BE without BOM"
        default:
            if let name = Self.names[encoding.rawValue] { return name }
            let localized = String.localizedName(of: encoding)
            return localized.isEmpty ? "Encoding \(encoding.rawValue)" : localized
        }
    }

    // MARK: - Internals

    init(cf: UInt32) {
        self.init(String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf)))
    }

    static let unicodeEncodings: Set<String.Encoding> = [
        .utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian,
    ]

    static func bom(for encoding: String.Encoding) -> [UInt8] {
        switch encoding {
        case .utf8: [0xEF, 0xBB, 0xBF]
        case .utf16LittleEndian: [0xFF, 0xFE]
        case .utf16BigEndian: [0xFE, 0xFF]
        case .utf32LittleEndian: [0xFF, 0xFE, 0x00, 0x00]
        case .utf32BigEndian: [0x00, 0x00, 0xFE, 0xFF]
        default: []
        }
    }

    /// Stable, locale-independent names; anything else falls back to Foundation's localized name.
    private static let names: [UInt: String] = {
        func cf(_ value: UInt32) -> UInt { CFStringConvertEncodingToNSStringEncoding(value) }
        return [
            String.Encoding.windowsCP1252.rawValue: "Windows Latin 1",
            String.Encoding.isoLatin1.rawValue: "ISO Latin 1",
            String.Encoding.macOSRoman.rawValue: "Mac Roman",
            String.Encoding.windowsCP1250.rawValue: "Windows Latin 2",
            String.Encoding.isoLatin2.rawValue: "ISO Latin 2",
            String.Encoding.windowsCP1251.rawValue: "Windows Cyrillic",
            String.Encoding.windowsCP1253.rawValue: "Windows Greek",
            String.Encoding.windowsCP1254.rawValue: "Windows Turkish",
            String.Encoding.shiftJIS.rawValue: "Shift JIS",
            String.Encoding.japaneseEUC.rawValue: "EUC-JP",
            String.Encoding.iso2022JP.rawValue: "ISO-2022-JP",
            String.Encoding.ascii.rawValue: "ASCII",
            cf(0x0A02): "KOI8-R",
            cf(0x0632): "GB18030",
            cf(0x0A03): "Big5",
            cf(0x0940): "EUC-KR",
        ]
    }()
}
