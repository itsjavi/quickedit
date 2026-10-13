import Foundation

/// A decoded, possibly truncated text file prefix for a Quick Look preview.
public struct TextPreview: Equatable, Sendable {
    public var text: String
    public var encoding: String.Encoding
    /// The file had more bytes than were read; `text` covers only the first part.
    public var isTruncated: Bool

    public init(text: String, encoding: String.Encoding, isTruncated: Bool) {
        self.text = text
        self.encoding = encoding
        self.isTruncated = isTruncated
    }
}

/// Tells text apart from video and other binary data, for files Quick Look hands to QuickEdit.
///
/// macOS maps `.ts` to `public.mpeg-2-transport-stream`, so the Quick Look extension receives both TypeScript sources
/// and real MPEG-TS video. Text gets a plain-text preview; anything else goes back to the system's movie preview.
public enum TextPreviewDetection {
    public enum Result: Equatable, Sendable {
        case text(TextPreview)
        /// MPEG-2 transport stream packets (188-byte, 192-byte M2TS or 204-byte FEC framing).
        case transportStream
        /// Other non-text data.
        case binary
    }

    /// Bytes read and previewed at most; larger files are truncated.
    public static let defaultByteLimit = 512 * 1024

    /// Classifies and decodes at most `byteLimit` bytes from the start of the file.
    public static func classify(contentsOf url: URL, byteLimit: Int = defaultByteLimit) throws -> Result {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // One extra byte tells "exactly the limit" from "truncated" without a separate size lookup.
        let data = try handle.read(upToCount: byteLimit + 1) ?? Data()
        if data.count > byteLimit {
            return classify(data.prefix(byteLimit), isTruncated: true)
        }
        return classify(data, isTruncated: false)
    }

    /// Classifies `data`, the start of a file. `isTruncated` says whether the file continues past it, so a multi-byte
    /// character cut at the end isn't mistaken for invalid text.
    public static func classify(_ data: Data, isTruncated: Bool) -> Result {
        let bytes = [UInt8](data)

        if let (bom, encoding, unit) = byteOrderMark(bytes) {
            // UTF-16/32 decode almost any bytes; a capture starting mid-packet with FF FE must stay video.
            if unit > 1, isTransportStream(bytes) { return .transportStream }
            let body = trimmed(bytes[bom...], encoding: encoding, unit: unit, isTruncated: isTruncated)
            guard let text = String(bytes: body, encoding: encoding) else { return .binary }
            return .text(TextPreview(text: text, encoding: encoding, isTruncated: isTruncated))
        }

        let hasNUL = bytes.contains(0)
        let utf8Body = isTruncated ? bytes[..<completeUTF8Prefix(bytes)] : bytes[...]
        let utf8Text = hasNUL ? nil : String(bytes: utf8Body, encoding: .utf8)

        // Packet sync bytes only count outside clean UTF-8 text (real streams are full of NUL and 0xFF stuffing), so a
        // source file that happens to have a 'G' at every 188th byte stays text.
        if utf8Text == nil, isTransportStream(bytes) { return .transportStream }
        // Text never contains NUL.
        if hasNUL || hasManyControlCharacters(bytes) { return .binary }

        if let utf8Text {
            return .text(TextPreview(text: utf8Text, encoding: .utf8, isTruncated: isTruncated))
        }
        // Windows-1252 leaves five bytes undefined; ISO Latin-1 decodes anything.
        for encoding in [String.Encoding.windowsCP1252, .isoLatin1] {
            if let text = String(bytes: bytes, encoding: encoding) {
                return .text(TextPreview(text: text, encoding: encoding, isTruncated: isTruncated))
            }
        }
        return .binary
    }

    /// Whether MPEG-TS sync bytes (0x47) repeat at a packet stride over the first packets, from any start offset
    /// (captures can begin mid-packet).
    public static func isTransportStream(_ bytes: [UInt8]) -> Bool {
        let syncByte: UInt8 = 0x47
        let minimumPackets = 3
        let checkedPackets = 8
        // (packet size, offset of the sync byte inside the packet)
        let layouts = [(188, 0), (192, 4), (204, 0)]
        for (size, offset) in layouts {
            let packets = min(checkedPackets, bytes.count / size)
            guard packets >= minimumPackets else { continue }
            for start in 0..<size {
                var matches = true
                for packet in 0..<packets {
                    let index = start + offset + packet * size
                    if index >= bytes.count || bytes[index] != syncByte {
                        matches = false
                        break
                    }
                }
                if matches { return true }
            }
        }
        return false
    }

    // MARK: - Helpers

    private static func byteOrderMark(_ bytes: [UInt8]) -> (length: Int, encoding: String.Encoding, unit: Int)? {
        // UTF-32 LE first: its BOM starts with the UTF-16 LE one.
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) { return (4, .utf32LittleEndian, 4) }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) { return (4, .utf32BigEndian, 4) }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return (3, .utf8, 1) }
        if bytes.starts(with: [0xFF, 0xFE]) { return (2, .utf16LittleEndian, 2) }
        if bytes.starts(with: [0xFE, 0xFF]) { return (2, .utf16BigEndian, 2) }
        return nil
    }

    /// Drops a partial code unit, character or UTF-16 surrogate pair left at the end by truncation.
    private static func trimmed(
        _ body: ArraySlice<UInt8>, encoding: String.Encoding, unit: Int, isTruncated: Bool
    ) -> ArraySlice<UInt8> {
        guard isTruncated else { return body }
        if unit == 1 { return body.prefix(completeUTF8Prefix(Array(body))) }
        var count = body.count - body.count % unit
        if unit == 2, count >= 2 {
            let first = body[body.startIndex + count - 2]
            let second = body[body.startIndex + count - 1]
            let highByte = encoding == .utf16LittleEndian ? second : first
            if (0xD8...0xDB).contains(highByte) { count -= 2 }
        }
        return body.prefix(count)
    }

    /// The length of `bytes` without a trailing, incomplete UTF-8 sequence.
    static func completeUTF8Prefix(_ bytes: [UInt8]) -> Int {
        var index = bytes.count
        // Walk back over at most three continuation bytes to the lead byte of the last sequence.
        var continuation = 0
        while index > 0, continuation < 3, bytes[index - 1] & 0xC0 == 0x80 {
            index -= 1
            continuation += 1
        }
        guard index > 0 else { return bytes.count }
        let lead = bytes[index - 1]
        let expected: Int
        switch lead {
        case 0xC0...0xDF: expected = 1
        case 0xE0...0xEF: expected = 2
        case 0xF0...0xF7: expected = 3
        default: return bytes.count  // ASCII or a stray byte: nothing to trim
        }
        return continuation < expected ? index - 1 : bytes.count
    }

    /// More than 5% C0 control characters other than whitespace, backspace and escape (used by terminal logs).
    private static func hasManyControlCharacters(_ bytes: [UInt8]) -> Bool {
        let allowed: Set<UInt8> = [0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1B]
        let controls = bytes.reduce(0) { count, byte in
            byte < 0x20 && !allowed.contains(byte) ? count + 1 : count
        }
        return controls * 20 > bytes.count
    }
}
