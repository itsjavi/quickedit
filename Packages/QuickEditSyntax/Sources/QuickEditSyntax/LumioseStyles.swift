import Foundation

/// A Lumiose `<style>` / `<style global>` block in a `.stsx` / `.sjsx` component file.
struct StyleBlock: Equatable {
    /// From `<style` through `</style>` (or the end of the text when unclosed).
    let range: NSRange
    /// The raw CSS between the opening tag's `>` and `</style`.
    let content: NSRange
}

/// Where the stylesheets and `$name.path` constant references are in a Lumiose component file.
///
/// Follows Lumiose's own TextMate grammar (`packages/vscode/syntaxes/stsx.tmLanguage.json`): a block starts at
/// `<style` followed by whitespace or `>` anywhere outside comments and strings, its CSS starts after the opening
/// tag's `>` (quoted attribute values may contain `>`) and ends before the first `</style\s*>`, or at the end of
/// the text. References are `$` + identifier + `.identifier`* inside the CSS, outside CSS comments and strings.
///
/// The JS lexer is deliberately small: it knows comments, quoted strings (which end at a line break, so an
/// apostrophe in JSX text only hides the rest of its line) and template literals with `${…}` nesting.
struct StyleScan: Equatable {
    var blocks: [StyleBlock] = []
    /// Sorted `$` references, in UTF-16 offsets.
    var references: [NSRange] = []

    /// The CSS ranges, sorted: what the TSX/JSX parser sees as blank.
    var contents: [NSRange] { blocks.map(\.content).filter { $0.length > 0 } }

    static func scan(_ text: NSString) -> StyleScan {
        let length = text.length
        guard length > 0 else { return StyleScan() }
        var units = [unichar](repeating: 0, count: length)
        units.withUnsafeMutableBufferPointer { text.getCharacters($0.baseAddress!, range: NSRange(location: 0, length: length)) }
        return units.withUnsafeBufferPointer { buffer in
            var scanner = Scanner(units: buffer)
            return scanner.run()
        }
    }

    /// Blanks the CSS of every block in a chunk read at `location`, keeping line breaks.
    static func blank(_ ranges: [NSRange], in buffer: UnsafeMutableBufferPointer<unichar>, at location: Int) {
        forEach(ranges, intersecting: NSRange(location: location, length: buffer.count)) { range in
            for index in (range.location - location)..<(range.upperBound - location) {
                let unit = buffer[index]
                if unit != 0x0A && unit != 0x0D { buffer[index] = 0x20 }
            }
        }
    }

    /// Turns each reference into a plain CSS identifier of the same length (`$theme.color.ink` →
    /// `_theme_color_ink`) so the CSS grammar parses the declaration around it.
    static func neutralize(_ references: [NSRange], in buffer: UnsafeMutableBufferPointer<unichar>, at location: Int) {
        forEach(references, intersecting: NSRange(location: location, length: buffer.count)) { range in
            for index in (range.location - location)..<(range.upperBound - location) {
                let unit = buffer[index]
                if unit == 0x24 || unit == 0x2E { buffer[index] = 0x5F }  // $ and . → _
            }
        }
    }

    /// Calls `body` with the part of each sorted range that intersects `window`.
    static func forEach(_ ranges: [NSRange], intersecting window: NSRange, _ body: (NSRange) -> Void) {
        var low = 0
        var high = ranges.count
        while low < high {
            let mid = (low + high) / 2
            if ranges[mid].upperBound <= window.location { low = mid + 1 } else { high = mid }
        }
        var index = low
        while index < ranges.count, ranges[index].location < window.upperBound {
            if let clipped = ranges[index].clipped(to: window) { body(clipped) }
            index += 1
        }
    }

    /// Ranges of the new text whose blanking changed, other than the edited text itself: a typed `</style>` or a
    /// deleted `<style` re-blanks or reveals code far from the edit, which tree-sitter must be told about. Works
    /// for any per-unit mask, e.g. `references` (neutralized in the stylesheet layers).
    static func maskChanges(old: [NSRange], new: [NSRange], replacing oldRange: NSRange, with length: Int) -> [NSRange] {
        let delta = length - oldRange.length
        var before = IndexSet()
        for range in old {
            if range.location < oldRange.location {
                before.insert(integersIn: range.location..<min(range.upperBound, oldRange.location))
            }
            if range.upperBound > oldRange.upperBound {
                let start = max(range.location, oldRange.upperBound)
                before.insert(integersIn: (start + delta)..<(range.upperBound + delta))
            }
        }
        var after = IndexSet()
        for range in new { after.insert(integersIn: range.location..<range.upperBound) }
        var changed = before.symmetricDifference(after)
        changed.remove(integersIn: oldRange.location..<(oldRange.location + length))
        return changed.rangeView.map { NSRange(location: $0.lowerBound, length: $0.count) }
    }
}

private struct Scanner {
    let units: UnsafeBufferPointer<unichar>
    var result = StyleScan()

    init(units: UnsafeBufferPointer<unichar>) {
        self.units = units
    }

    private enum Mode {
        case code(braces: Int)
        case template
    }

    mutating func run() -> StyleScan {
        let count = units.count
        var stack: [Mode] = [.code(braces: 0)]
        var index = 0
        while index < count {
            let unit = units[index]
            switch stack[stack.count - 1] {
            case .template:
                if unit == 0x5C {  // \
                    index += 2
                } else if unit == 0x60 {  // `
                    stack.removeLast()
                    index += 1
                } else if unit == 0x24, at(index + 1) == 0x7B {  // ${
                    stack.append(.code(braces: 0))
                    index += 2
                } else {
                    index += 1
                }
            case .code(let braces):
                switch unit {
                case 0x2F where at(index + 1) == 0x2F:  // //
                    index = lineEnd(from: index)
                case 0x2F where at(index + 1) == 0x2A:  // /*
                    index = blockCommentEnd(from: index + 2)
                case 0x22, 0x27:  // " '
                    index = stringEnd(from: index + 1, quote: unit, stopAtLineBreak: true)
                case 0x60:
                    stack.append(.template)
                    index += 1
                case 0x7B:
                    stack[stack.count - 1] = .code(braces: braces + 1)
                    index += 1
                case 0x7D:
                    if braces == 0, stack.count > 1 {
                        stack.removeLast()  // the end of a template's ${…}
                    } else {
                        stack[stack.count - 1] = .code(braces: max(0, braces - 1))
                    }
                    index += 1
                case 0x3C where isStyleOpening(at: index):  // <style
                    index = block(from: index)
                default:
                    index += 1
                }
            }
        }
        return result
    }

    private func at(_ index: Int) -> unichar {
        index < units.count ? units[index] : 0
    }

    private func lineEnd(from index: Int) -> Int {
        var index = index
        while index < units.count, units[index] != 0x0A { index += 1 }
        return index
    }

    private func blockCommentEnd(from index: Int) -> Int {
        var index = index
        while index < units.count {
            if units[index] == 0x2A, at(index + 1) == 0x2F { return index + 2 }
            index += 1
        }
        return units.count
    }

    private func stringEnd(from index: Int, quote: unichar, stopAtLineBreak: Bool) -> Int {
        var index = index
        while index < units.count {
            let unit = units[index]
            if unit == 0x5C {
                index += 2
                continue
            }
            if unit == quote { return index + 1 }
            if stopAtLineBreak, unit == 0x0A { return index }
            index += 1
        }
        return units.count
    }

    private static let style: [unichar] = Array("style".utf16)

    private func matches(_ word: [unichar], at index: Int) -> Bool {
        guard index + word.count <= units.count else { return false }
        for offset in 0..<word.count where units[index + offset] != word[offset] { return false }
        return true
    }

    private func isStyleOpening(at index: Int) -> Bool {
        guard matches(Self.style, at: index + 1) else { return false }
        let next = at(index + 6)
        return next == 0x3E || next == 0x20 || next == 0x09 || next == 0x0A || next == 0x0D
    }

    /// Records the block starting at `<style` and returns the index after it.
    private mutating func block(from start: Int) -> Int {
        let count = units.count
        // The opening tag: attributes until `>`; quoted values may hold `>`.
        var index = start + 6
        var contentStart = count
        while index < count {
            let unit = units[index]
            if unit == 0x22 || unit == 0x27 {
                index = stringEnd(from: index + 1, quote: unit, stopAtLineBreak: false)
            } else if unit == 0x3E {
                contentStart = index + 1
                break
            } else {
                index += 1
            }
        }
        // The first `</style\s*>`.
        var contentEnd = count
        var end = count
        index = contentStart
        while index < count {
            if units[index] == 0x3C, at(index + 1) == 0x2F, matches(Self.style, at: index + 2) {
                var close = index + 7
                while close < count, units[close] == 0x20 || units[close] == 0x09 || units[close] == 0x0A
                    || units[close] == 0x0D
                {
                    close += 1
                }
                if close < count, units[close] == 0x3E {
                    contentEnd = index
                    end = close + 1
                    break
                }
            }
            index += 1
        }
        let content = NSRange(location: contentStart, length: max(0, contentEnd - contentStart))
        result.blocks.append(StyleBlock(range: NSRange(location: start, length: end - start), content: content))
        scanReferences(in: content)
        return end
    }

    private static func isIdentifierStart(_ unit: unichar) -> Bool {
        (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A) || unit == 0x5F
    }

    private static func isIdentifier(_ unit: unichar) -> Bool {
        isIdentifierStart(unit) || (unit >= 0x30 && unit <= 0x39)
    }

    private mutating func scanReferences(in content: NSRange) {
        var index = content.location
        let end = content.upperBound
        while index < end {
            let unit = units[index]
            if unit == 0x2F, index + 1 < end, units[index + 1] == 0x2A {  // CSS comment
                index = min(end, blockCommentEnd(from: index + 2))
            } else if unit == 0x22 || unit == 0x27 {  // CSS string
                index = min(end, stringEnd(from: index + 1, quote: unit, stopAtLineBreak: true))
            } else if unit == 0x24, index + 1 < end, Self.isIdentifierStart(units[index + 1]) {
                var cursor = index + 2
                while cursor < end, Self.isIdentifier(units[cursor]) { cursor += 1 }
                while cursor + 1 < end, units[cursor] == 0x2E, Self.isIdentifierStart(units[cursor + 1]) {
                    cursor += 2
                    while cursor < end, Self.isIdentifier(units[cursor]) { cursor += 1 }
                }
                result.references.append(NSRange(location: index, length: cursor - index))
                index = cursor
            } else {
                index += 1
            }
        }
    }
}
