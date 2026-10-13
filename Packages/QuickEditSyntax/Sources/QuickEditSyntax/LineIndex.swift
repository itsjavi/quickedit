import Foundation
import SwiftTreeSitter

/// UTF-16 offsets of line starts (after each `\n`, which is how tree-sitter counts rows), kept current across
/// edits so tree-sitter points can be computed without rescanning the text.
struct LineIndex {
    private(set) var starts: [Int] = [0]

    init() {}

    init(text: NSString) {
        starts = [0] + Self.lineStarts(in: text, range: NSRange(location: 0, length: text.length))
    }

    /// Updates the index after `oldRange` was replaced by `replacementLength` units of `newText`.
    mutating func applyEdit(oldRange: NSRange, replacementLength: Int, newText: NSString) {
        let delta = replacementLength - oldRange.length
        // Starts after a newline inside the old range are gone; later ones shift.
        let firstRemoved = firstIndex(greaterThan: oldRange.location)
        let firstKept = firstIndex(greaterThan: oldRange.upperBound)
        let inserted = Self.lineStarts(
            in: newText, range: NSRange(location: oldRange.location, length: replacementLength))
        if delta != 0 {
            for index in firstKept..<starts.count { starts[index] += delta }
        }
        starts.replaceSubrange(firstRemoved..<firstKept, with: inserted)
    }

    /// The row of the line containing `offset`.
    func row(at offset: Int) -> Int {
        firstIndex(greaterThan: offset) - 1
    }

    /// The tree-sitter point (row, UTF-16 byte column) of a UTF-16 offset.
    func point(at offset: Int) -> Point {
        let row = row(at: offset)
        return Point(row: row, column: (offset - starts[row]) * 2)
    }

    /// The whole lines from the one containing `range.location` through the one containing `range.upperBound`
    /// (so text pushed onto a new line by an inserted newline is included), with the final newline.
    func lineRange(covering range: NSRange, length: Int) -> NSRange {
        let start = starts[row(at: range.location)]
        let lastRow = row(at: range.upperBound)
        let end = lastRow + 1 < starts.count ? starts[lastRow + 1] : length
        return NSRange(location: start, length: max(0, min(end, length) - start))
    }

    /// Index of the first start greater than `offset` (binary search).
    private func firstIndex(greaterThan offset: Int) -> Int {
        var low = 0
        var high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= offset { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Offsets just after each `\n` in `range`.
    static func lineStarts(in text: NSString, range: NSRange) -> [Int] {
        var result: [Int] = []
        TextChunks.forEachChunk(of: text, in: range) { buffer, location in
            for (index, unit) in buffer.enumerated() where unit == 0x0A {
                result.append(location + index + 1)
            }
        }
        return result
    }
}

/// Reads an `NSString` in UTF-16 chunks without copying the whole text.
enum TextChunks {
    static let size = 8192

    static func forEachChunk(of text: NSString, in range: NSRange, _ body: (UnsafeBufferPointer<unichar>, Int) -> Void) {
        guard range.length > 0 else { return }
        withUnsafeTemporaryAllocation(of: unichar.self, capacity: size) { buffer in
            var location = range.location
            while location < range.upperBound {
                let count = min(size, range.upperBound - location)
                text.getCharacters(buffer.baseAddress!, range: NSRange(location: location, length: count))
                body(UnsafeBufferPointer(rebasing: buffer[..<count]), location)
                location += count
            }
        }
    }

    /// Rewrites a chunk read at a UTF-16 location in place (e.g. blanking embedded stylesheets) before
    /// tree-sitter sees it. Must keep every line break so rows and columns stay put.
    typealias Transform = (UnsafeMutableBufferPointer<unichar>, Int) -> Void

    /// The tree-sitter read callback: UTF-16LE data starting at a byte offset.
    static func readBlock(for text: NSString, transform: Transform? = nil) -> Parser.ReadBlock {
        let length = text.length
        return { byteOffset, _ in
            let location = byteOffset / 2
            guard location < length else { return nil }
            var count = min(size, length - location)
            // Don't split a surrogate pair across chunks.
            if location + count < length, UTF16.isLeadSurrogate(text.character(at: location + count - 1)) {
                count += 1
            }
            var data = Data(count: count * 2)
            data.withUnsafeMutableBytes { raw in
                let units = raw.bindMemory(to: unichar.self)
                text.getCharacters(units.baseAddress!, range: NSRange(location: location, length: count))
                transform?(units, location)
            }
            return data
        }
    }
}
