import Foundation

/// Where a text's risky characters are (UTF-16 offsets, ascending). Built once, then updated from each edit, so the
/// status bar's count doesn't rescan a large file on every keystroke.
public final class RiskyIndex {
    public private(set) var locations: [Int] = []

    public init() {}

    public var count: Int { locations.count }

    public func rebuild(_ text: NSString) {
        locations = RiskyCharacters.scan(text, in: NSRange(location: 0, length: text.length)).map(\.range.location)
    }

    /// Updates the locations for an edit of `text`: `editedRange` is the new text, which is `delta` UTF-16 units
    /// longer than what it replaced (an `NSTextStorage` edit).
    public func edit(editedRange: NSRange, changeInLength delta: Int, in text: NSString) {
        // One unit of margin on each side, widened to whole surrogate pairs, covers pairs the edit split or joined.
        var low = max(editedRange.location - 1, 0)
        if low > 0, low < text.length, UTF16.isTrailSurrogate(text.character(at: low)) { low -= 1 }
        let oldEnd = editedRange.upperBound - delta + 1
        let newEnd = min(editedRange.upperBound + 1, text.length)
        let first = LineIndex.firstIndex(in: locations, notBefore: low)
        let end = LineIndex.firstIndex(in: locations, notBefore: oldEnd)
        let fresh = low < newEnd
            ? RiskyCharacters.scan(text, in: NSRange(location: low, length: newEnd - low)).map(\.range.location)
            : []
        locations.replaceSubrange(first..<end, with: fresh)
        if delta != 0 {
            for index in (first + fresh.count)..<locations.count { locations[index] += delta }
        }
    }
}
