import Foundation

/// UTF-16 offsets where logical lines start, rebuilt lazily after edits. Handles LF, CRLF and CR line endings.
final class LineIndex {
    private var starts: [Int] = [0]
    private var isValid = false

    func invalidate() {
        isValid = false
    }

    func lineStarts(in text: NSString) -> [Int] {
        if !isValid {
            var result = [0]
            var index = 0
            while index < text.length {
                var end = 0
                var contentsEnd = 0
                text.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
                // A line break: the next line starts at `end`, even when that is the empty line at the very end.
                if end > contentsEnd { result.append(end) }
                index = end
            }
            starts = result
            isValid = true
        }
        return starts
    }

    func lineCount(in text: NSString) -> Int {
        lineStarts(in: text).count
    }

    /// The 0-based line containing `location`.
    func line(of location: Int, in text: NSString) -> Int {
        let starts = lineStarts(in: text)
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// The UTF-16 offset where the 0-based `line` starts (clamped).
    func start(ofLine line: Int, in text: NSString) -> Int {
        let starts = lineStarts(in: text)
        return starts[min(max(line, 0), starts.count - 1)]
    }
}
