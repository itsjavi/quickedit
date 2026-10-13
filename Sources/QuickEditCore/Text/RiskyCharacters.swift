import Foundation

public enum RiskyCategory: String, Sendable {
    case zeroWidth, bidiControl, unusualSpace, softHyphen, control, byteOrderMark, lineSeparator
}

/// An invisible or look-alike character worth marking in the editor.
public struct RiskyCharacter: Equatable, Sendable {
    /// UTF-16 range in the scanned string (length 2 for characters outside the BMP).
    public let range: NSRange
    public let scalar: Unicode.Scalar
    public let category: RiskyCategory

    public init(range: NSRange, scalar: Unicode.Scalar, category: RiskyCategory) {
        self.range = range
        self.scalar = scalar
        self.category = category
    }

    /// The Unicode name and code point, e.g. "ZERO WIDTH SPACE U+200B" or "ESCAPE U+001B".
    public var name: String { RiskyCharacters.name(of: scalar) }
}

/// Finds characters that change meaning or rendering invisibly (Trojan Source and friends): zero-width characters and
/// invisible operators, Unicode tag characters, bidi controls, non-breaking and other unusual spaces, soft hyphens,
/// C0/C1 controls other than tab/LF/CR, a BOM inside the text, and Unicode line/paragraph separators.
public enum RiskyCharacters {
    public static func isRisky(_ scalar: Unicode.Scalar) -> RiskyCategory? {
        switch scalar.value {
        case 0x09, 0x0A, 0x0D: nil
        case 0x00...0x1F, 0x7F...0x9F: .control
        case 0xAD: .softHyphen
        case 0xA0, 0x1680, 0x2000...0x200A, 0x202F, 0x205F, 0x3000, 0x3164, 0xFFA0: .unusualSpace
        case 0x200B...0x200D, 0x2060...0x2064, 0x180E, 0xE0000...0xE007F: .zeroWidth
        case 0x200E, 0x200F, 0x061C, 0x202A...0x202E, 0x2066...0x2069: .bidiControl
        case 0xFEFF: .byteOrderMark
        case 0x2028, 0x2029: .lineSeparator
        default: nil
        }
    }

    /// Risky characters inside `range` (UTF-16), for marking the visible part of the editor on each redraw. A
    /// surrogate pair cut by the start of the range belongs to the previous range and is skipped.
    public static func scan(_ text: NSString, in range: NSRange) -> [RiskyCharacter] {
        var found: [RiskyCharacter] = []
        forEachRisky(in: text, range: range) { range, scalar, category in
            found.append(RiskyCharacter(range: range, scalar: scalar, category: category))
        }
        return found
    }

    /// The number of risky characters in the whole string, for the status bar.
    public static func count(in text: NSString) -> Int {
        var count = 0
        forEachRisky(in: text, range: NSRange(location: 0, length: text.length)) { _, _, _ in count += 1 }
        return count
    }

    // MARK: - Scanning

    private static let chunkSize = 16_384

    private static func forEachRisky(
        in text: NSString, range: NSRange, _ body: (NSRange, Unicode.Scalar, RiskyCategory) -> Void
    ) {
        let length = text.length
        guard range.location != NSNotFound, range.location < length, range.length > 0 else { return }
        let start = max(0, range.location)
        let end = range.length >= length - start ? length : start + range.length
        if let pointer = CFStringGetCharactersPtr(text as CFString) {
            scanUnits(UnsafeBufferPointer(start: pointer, count: length), from: start, to: end, base: 0, body)
            return
        }
        var buffer = [UInt16](repeating: 0, count: min(chunkSize, end - start) + 1)
        var chunkStart = start
        while chunkStart < end {
            let chunkEnd = min(end, chunkStart + chunkSize)
            let fetchEnd = min(length, chunkEnd + 1)  // one unit of lookahead for a pair cut by the chunk end
            buffer.withUnsafeMutableBufferPointer { units in
                text.getCharacters(units.baseAddress!, range: NSRange(location: chunkStart, length: fetchEnd - chunkStart))
                let fetched = UnsafeBufferPointer(rebasing: units[0..<(fetchEnd - chunkStart)])
                scanUnits(fetched, from: 0, to: chunkEnd - chunkStart, base: chunkStart, body)
            }
            chunkStart = chunkEnd
        }
    }

    /// Scans `units[from..<to]`, reading past `to` only to complete a surrogate pair. `base` maps buffer offsets to
    /// string offsets.
    private static func scanUnits(
        _ units: UnsafeBufferPointer<UInt16>, from: Int, to: Int, base: Int,
        _ body: (NSRange, Unicode.Scalar, RiskyCategory) -> Void
    ) {
        var index = from
        while index < to {
            let unit = units[index]
            if unit >= 0x20, unit < 0x7F {  // printable ASCII: the overwhelmingly common case
                index += 1
                continue
            }
            if UTF16.isLeadSurrogate(unit) {
                if index + 1 < units.count, UTF16.isTrailSurrogate(units[index + 1]) {
                    let scalar = Unicode.Scalar(UTF16.decode(UTF16.EncodedScalar([unit, units[index + 1]])).value)!
                    if let category = isRisky(scalar) {
                        body(NSRange(location: base + index, length: 2), scalar, category)
                    }
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            if !UTF16.isTrailSurrogate(unit), let scalar = Unicode.Scalar(unit), let category = isRisky(scalar) {
                body(NSRange(location: base + index, length: 1), scalar, category)
            }
            index += 1
        }
    }

    // MARK: - Names

    static func name(of scalar: Unicode.Scalar) -> String {
        let hex = String(scalar.value, radix: 16, uppercase: true)
        let codePoint = "U+" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
        let name = scalar.properties.name ?? controlName(scalar.value)
        return name.map { "\($0) \(codePoint)" } ?? codePoint
    }

    /// Control characters have no Unicode name; these are their standard aliases.
    private static func controlName(_ value: UInt32) -> String? {
        switch value {
        case 0x00...0x1F: c0Names[Int(value)]
        case 0x7F: "DELETE"
        case 0x80...0x9F: c1Names[Int(value - 0x80)]
        default: nil
        }
    }

    private static let c0Names = [
        "NULL", "START OF HEADING", "START OF TEXT", "END OF TEXT", "END OF TRANSMISSION", "ENQUIRY", "ACKNOWLEDGE",
        "BELL", "BACKSPACE", "CHARACTER TABULATION", "LINE FEED", "LINE TABULATION", "FORM FEED", "CARRIAGE RETURN",
        "SHIFT OUT", "SHIFT IN", "DATA LINK ESCAPE", "DEVICE CONTROL ONE", "DEVICE CONTROL TWO", "DEVICE CONTROL THREE",
        "DEVICE CONTROL FOUR", "NEGATIVE ACKNOWLEDGE", "SYNCHRONOUS IDLE", "END OF TRANSMISSION BLOCK", "CANCEL",
        "END OF MEDIUM", "SUBSTITUTE", "ESCAPE", "FILE SEPARATOR", "GROUP SEPARATOR", "RECORD SEPARATOR",
        "UNIT SEPARATOR",
    ]

    private static let c1Names = [
        "PADDING CHARACTER", "HIGH OCTET PRESET", "BREAK PERMITTED HERE", "NO BREAK HERE", "INDEX", "NEXT LINE",
        "START OF SELECTED AREA", "END OF SELECTED AREA", "CHARACTER TABULATION SET",
        "CHARACTER TABULATION WITH JUSTIFICATION", "LINE TABULATION SET", "PARTIAL LINE FORWARD",
        "PARTIAL LINE BACKWARD", "REVERSE LINE FEED", "SINGLE SHIFT TWO", "SINGLE SHIFT THREE", "DEVICE CONTROL STRING",
        "PRIVATE USE ONE", "PRIVATE USE TWO", "SET TRANSMIT STATE", "CANCEL CHARACTER", "MESSAGE WAITING",
        "START OF GUARDED AREA", "END OF GUARDED AREA", "START OF STRING", "SINGLE GRAPHIC CHARACTER INTRODUCER",
        "SINGLE CHARACTER INTRODUCER", "CONTROL SEQUENCE INTRODUCER", "STRING TERMINATOR", "OPERATING SYSTEM COMMAND",
        "PRIVACY MESSAGE", "APPLICATION PROGRAM COMMAND",
    ]
}
