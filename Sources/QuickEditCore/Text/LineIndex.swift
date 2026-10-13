import Foundation

/// UTF-16 offsets where logical lines start. Built once, then updated from each edit, so typing in a 300 MB file
/// doesn't rescan it. Line breaks are the ones `NSString.getLineStart` knows: LF, CR, CRLF, NEL, LS and PS.
public final class LineIndex {
    private var starts: [Int] = [0]
    private var isValid = false

    public init() {}

    public func invalidate() {
        isValid = false
    }

    public func lineStarts(in text: NSString) -> [Int] {
        if !isValid {
            starts = [0] + Self.lineStarts(in: text, from: 1, through: text.length)
            isValid = true
        }
        return starts
    }

    public func lineCount(in text: NSString) -> Int {
        lineStarts(in: text).count
    }

    /// The 0-based line containing `location`.
    public func line(of location: Int, in text: NSString) -> Int {
        let starts = lineStarts(in: text)
        return Self.lastIndex(in: starts, notAfter: location)
    }

    /// The UTF-16 offset where the 0-based `line` starts (clamped).
    public func start(ofLine line: Int, in text: NSString) -> Int {
        let starts = lineStarts(in: text)
        return starts[min(max(line, 0), starts.count - 1)]
    }

    /// Updates the index for an edit of `text`: `editedRange` is the new text, which is `delta` UTF-16 units longer
    /// than what it replaced (an `NSTextStorage` edit). Does nothing while the index is invalid.
    public func edit(editedRange: NSRange, changeInLength delta: Int, in text: NSString) {
        guard isValid else { return }
        // Whether `p` starts a line depends on the units at p - 1 and p (a CR followed by an LF), so starts from the
        // edit's location to one past its end are derived again; later ones only move by `delta`.
        let low = max(editedRange.location, 1)
        let oldHigh = editedRange.upperBound - delta + 1
        let newHigh = min(editedRange.upperBound + 1, text.length)
        let first = Self.firstIndex(in: starts, notBefore: low)
        let end = Self.firstIndex(in: starts, notBefore: oldHigh + 1)
        let fresh = low <= newHigh ? Self.lineStarts(in: text, from: low, through: newHigh) : []
        starts.replaceSubrange(first..<end, with: fresh)
        if delta != 0 {
            starts.withUnsafeMutableBufferPointer { buffer in
                for index in (first + fresh.count)..<buffer.count { buffer[index] += delta }
            }
        }
    }

    // MARK: - Scanning

    private static let chunkSize = 65_536

    /// The line starts `p` with `low <= p <= high` (both at least 1): positions right after a line break, except
    /// between the CR and LF of a CRLF.
    static func lineStarts(in text: NSString, from low: Int, through high: Int) -> [Int] {
        let length = text.length
        let firstUnit = max(low, 1) - 1
        let lastUnit = min(high, length) - 1
        guard firstUnit <= lastUnit else { return [] }
        var result: [Int] = []
        if let pointer = CFStringGetCharactersPtr(text as CFString) {
            scan(UnsafeBufferPointer(start: pointer, count: length), from: firstUnit, through: lastUnit, base: 0, into: &result)
            return result
        }
        var buffer = [UInt16](repeating: 0, count: min(chunkSize, lastUnit - firstUnit + 1) + 1)
        var chunkStart = firstUnit
        while chunkStart <= lastUnit {
            let chunkLast = min(lastUnit, chunkStart + chunkSize - 1)
            let fetchEnd = min(length, chunkLast + 2)  // one unit of lookahead for a CR at the chunk's end
            buffer.withUnsafeMutableBufferPointer { units in
                text.getCharacters(units.baseAddress!, range: NSRange(location: chunkStart, length: fetchEnd - chunkStart))
                let fetched = UnsafeBufferPointer(rebasing: units[0..<(fetchEnd - chunkStart)])
                scan(fetched, from: 0, through: chunkLast - chunkStart, base: chunkStart, into: &result)
            }
            chunkStart = chunkLast + 1
        }
        return result
    }

    /// Appends `base + u + 1` for each line break ending at unit `u` in `from...through`. Reads one unit past
    /// `through`, when there is one, to tell a CR from the first half of a CRLF.
    private static func scan(_ units: UnsafeBufferPointer<UInt16>, from: Int, through: Int, base: Int, into result: inout [Int]) {
        var index = from
        while index <= through {
            let unit = units[index]
            if unit > 0x0D, unit < 0x85 {  // most text
                index += 1
                continue
            }
            switch unit {
            case 0x0A, 0x85, 0x2028, 0x2029:
                result.append(base + index + 1)
            case 0x0D:
                if index + 1 >= units.count || units[index + 1] != 0x0A { result.append(base + index + 1) }
            default:
                break
            }
            index += 1
        }
    }

    /// The first index whose value is at least `value` (`values.count` when none is).
    static func firstIndex(in values: [Int], notBefore value: Int) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let mid = (low + high) / 2
            if values[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// The last index whose value is at most `value` (0 when none is).
    static func lastIndex(in values: [Int], notAfter value: Int) -> Int {
        max(firstIndex(in: values, notBefore: value + 1) - 1, 0)
    }
}
