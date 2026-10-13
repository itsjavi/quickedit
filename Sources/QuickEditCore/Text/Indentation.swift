import Foundation

public enum IndentStyle: String, Sendable {
    case tabs, spaces
}

public struct Indentation: Equatable, Sendable {
    public var style: IndentStyle
    /// Columns per indentation level: the tab width for tabs, the number of spaces otherwise.
    public var width: Int

    public init(style: IndentStyle, width: Int) {
        self.style = style
        self.width = max(1, width)
    }

    public static func tabs(width: Int = 4) -> Indentation { Indentation(style: .tabs, width: width) }
    public static func spaces(_ width: Int) -> Indentation { Indentation(style: .spaces, width: width) }

    /// One level of indentation: `"\t"` or `width` spaces.
    public var unit: String { style == .tabs ? "\t" : String(repeating: " ", count: width) }
}

public enum IndentationDetector {
    /// Lines looked at by `detect`, enough for a confident guess without scanning huge files.
    static let maxSampledLines = 10_000

    /// Guesses the file's indentation from its first lines: tabs when more lines start with a tab than with spaces,
    /// otherwise spaces with the most common indentation change between consecutive lines. Blank lines and block
    /// comment continuations (` * `) are ignored. Returns nil when no line is indented. Tab indentation reports
    /// `tabWidth`, since the file can't tell how wide its tabs are.
    public static func detect(_ text: String, tabWidth: Int = 4) -> Indentation? {
        var tabLines = 0, spaceLines = 0
        var deltas = [Int](repeating: 0, count: 9)
        var previousSpaces = 0

        text.withUTF8Buffer { bytes in
            let count = bytes.count
            var index = 0
            var lines = 0
            while index < count, lines < maxSampledLines {
                lines += 1
                var spaces = 0
                let startsWithTab = bytes[index] == 0x09
                var hasTab = false
                while index < count, bytes[index] == 0x20 || bytes[index] == 0x09 {
                    if bytes[index] == 0x20 { spaces += 1 } else { hasTab = true }
                    index += 1
                }
                let first: UInt8? = index < count ? bytes[index] : nil
                // Skip to the next line.
                while index < count, bytes[index] != 0x0A, bytes[index] != 0x0D { index += 1 }
                if index < count, bytes[index] == 0x0D, index + 1 < count, bytes[index + 1] == 0x0A { index += 1 }
                index += 1

                guard let first, first != 0x0A, first != 0x0D else { continue }  // blank line
                if startsWithTab {
                    tabLines += 1
                    continue
                }
                if hasTab { continue }  // spaces then tabs: alignment noise
                if first == UInt8(ascii: "*"), spaces % 2 == 1 { continue }  // " * " in block comments
                if spaces > 0 { spaceLines += 1 }
                let delta = abs(spaces - previousSpaces)
                if delta > 0, delta < deltas.count { deltas[delta] += 1 }
                previousSpaces = spaces
            }
        }

        if tabLines == 0, spaceLines == 0 { return nil }
        if tabLines > spaceLines { return .tabs(width: tabWidth) }
        // Most common change in indentation; 1-space steps are usually alignment, so they only count when alone.
        var best = 0
        for width in 2..<deltas.count where deltas[width] > (best == 0 ? 0 : deltas[best]) {
            best = width
        }
        if best == 0 { best = deltas[1] > 0 ? 1 : 4 }
        return .spaces(best)
    }

    /// Re-indents the leading whitespace of every line: each `from` level becomes a `to` level, and leftover
    /// alignment columns stay as spaces. Line endings and everything after the leading whitespace are untouched.
    public static func convert(_ text: String, from: Indentation, to: Indentation) -> String {
        if from == to { return text }
        return text.withUTF8Buffer { bytes in
            var output = [UInt8]()
            output.reserveCapacity(bytes.count)
            let count = bytes.count
            var index = 0
            while index < count {
                var column = 0
                while index < count, bytes[index] == 0x20 || bytes[index] == 0x09 {
                    column = bytes[index] == 0x09 ? (column / from.width + 1) * from.width : column + 1
                    index += 1
                }
                let levels = column / from.width, remainder = column % from.width
                switch to.style {
                case .tabs:
                    output.append(contentsOf: repeatElement(0x09, count: levels))
                    output.append(contentsOf: repeatElement(0x20, count: remainder))
                case .spaces:
                    output.append(contentsOf: repeatElement(0x20, count: levels * to.width + remainder))
                }
                let lineStart = index
                while index < count, bytes[index] != 0x0A, bytes[index] != 0x0D { index += 1 }
                if index < count {
                    if bytes[index] == 0x0D, index + 1 < count, bytes[index + 1] == 0x0A { index += 1 }
                    index += 1
                }
                output.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[lineStart..<index]))
            }
            return String(decoding: output, as: UTF8.self)
        }
    }
}
