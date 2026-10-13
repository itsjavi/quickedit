import Foundation

public enum WhitespaceTransforms {
    /// Removes spaces and tabs before every line break and at the end of the text. Line endings stay exactly as they
    /// are, and other whitespace (form feeds, no-break spaces) is left alone.
    public static func trimmingTrailingWhitespace(_ text: String) -> String {
        text.withUTF8Buffer { bytes in
            var output = [UInt8]()
            output.reserveCapacity(bytes.count)
            var pendingStart: Int?
            var changed = false
            for index in bytes.indices {
                switch bytes[index] {
                case 0x20, 0x09:
                    if pendingStart == nil { pendingStart = index }
                case 0x0A, 0x0D:
                    if pendingStart != nil { changed = true }
                    pendingStart = nil
                    output.append(bytes[index])
                default:
                    if let start = pendingStart {
                        output.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[start..<index]))
                        pendingStart = nil
                    }
                    output.append(bytes[index])
                }
            }
            if pendingStart != nil { changed = true }
            return changed ? String(decoding: output, as: UTF8.self) : text
        }
    }

    /// Appends `lineEnding` unless the text is empty or already ends with a line break (of any kind).
    public static func ensuringFinalNewline(_ text: String, lineEnding: LineEnding) -> String {
        guard let last = text.utf8.last, last != 0x0A, last != 0x0D else { return text }
        return text + lineEnding.rawValue
    }
}
