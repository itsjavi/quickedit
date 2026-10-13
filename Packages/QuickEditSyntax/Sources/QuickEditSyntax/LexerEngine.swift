import Foundation

/// Formats without a maintained tree-sitter grammar, highlighted by a small line lexer.
enum SimpleLexer: Sendable, Hashable {
    /// Xcode build settings: `KEY[sdk=*] = value $(inherited) // comment`, `#include "other.xcconfig"`.
    case xcconfig
    /// Apple `.strings`: `"key" = "value";` with `/* */` and `//` comments, escapes and format specifiers.
    case appleStrings
    /// OpenStep property lists (`.pbxproj`): `key = value;`, `{ }`, `( )`, quoted strings, `/* */` comments.
    case openStep
}

/// Highlights with a `SimpleLexer`, one line at a time. The lexer state at each line start (inside a block comment
/// or a string) is cached and recomputed from the first edited line, so scrolling never rescans the whole file.
final class LexerEngine: HighlightEngine {
    private let lexer: SimpleLexer
    private var text: NSString = ""
    private var lines = LineIndex()
    /// The state at the start of each line, known for lines `0..<states.count`.
    private var states: [LineLexer.State] = [.normal]

    init(lexer: SimpleLexer) {
        self.lexer = lexer
    }

    func rebind(_ text: NSString) {
        self.text = text
    }

    func setText(_ text: NSString) {
        self.text = text
        lines = LineIndex(text: text)
        states = [.normal]
    }

    func applyEdit(replacing oldRange: NSRange, with replacementLength: Int, in newText: NSString) -> [NSRange] {
        let edited = NSRange(location: oldRange.location, length: replacementLength)
        let delimiters = CharacterSet(charactersIn: "\"/*")
        // The caller may pass the same mutable string again; then the deleted text can't be read.
        let deletedDelimiter =
            oldRange.length > 0
            && (text === newText || oldRange.upperBound > text.length
                || text.substring(with: oldRange).rangeOfCharacter(from: delimiters) != nil)
        let insertedDelimiter = newText.substring(with: edited).rangeOfCharacter(from: delimiters) != nil

        lines.applyEdit(oldRange: oldRange, replacementLength: replacementLength, newText: newText)
        text = newText
        let row = lines.row(at: oldRange.location)
        if states.count > row + 1 { states.removeSubrange((row + 1)...) }

        let lineRange = lines.lineRange(covering: edited, length: newText.length)
        // A quote or comment delimiter can change how every following line starts.
        if deletedDelimiter || insertedDelimiter {
            return [NSRange(location: lineRange.location, length: newText.length - lineRange.location)]
        }
        return [lineRange]
    }

    func tokens(in range: NSRange) -> [SyntaxToken] {
        let length = text.length
        guard let range = range.clipped(to: NSRange(location: 0, length: length)) else { return [] }
        let firstRow = lines.row(at: range.location)
        let lastRow = lines.row(at: range.upperBound - 1)
        var tokens: [SyntaxToken] = []
        var row = min(states.count - 1, firstRow)
        while row <= lastRow {
            let start = lines.starts[row]
            let end = row + 1 < lines.starts.count ? lines.starts[row + 1] : length
            let line = text.substring(with: NSRange(location: start, length: end - start)).utf16
            var lexer = LineLexer(kind: self.lexer, units: Array(line))
            let next = lexer.run(from: states[row])
            if row + 1 == states.count, row + 1 < lines.starts.count {
                states.append(next)
            }
            if row >= firstRow {
                for token in lexer.tokens {
                    let tokenRange = NSRange(location: start + token.start, length: token.end - token.start)
                    guard let clipped = tokenRange.clipped(to: range) else { continue }
                    if let last = tokens.last, last.kind == token.kind, last.range.upperBound == clipped.location {
                        tokens[tokens.count - 1] = SyntaxToken(
                            range: NSRange(location: last.range.location, length: clipped.upperBound - last.range.location),
                            kind: token.kind)
                    } else {
                        tokens.append(SyntaxToken(range: clipped, kind: token.kind))
                    }
                }
            }
            row += 1
        }
        return tokens
    }
}

/// Lexes one line (with its line break) of a `SimpleLexer` format.
struct LineLexer {
    enum State: Sendable, Equatable {
        case normal
        case blockComment
        /// Inside a double-quoted string; `key` when it's the key of an entry.
        case string(key: Bool)
    }

    struct Token {
        let start: Int
        let end: Int
        let kind: TokenKind
    }

    let kind: SimpleLexer
    let units: [unichar]
    private(set) var tokens: [Token] = []
    private var index = 0
    /// `.strings`/OpenStep: whether `=` has been seen in the current entry (strings before it are keys).
    private var afterEquals = false

    init(kind: SimpleLexer, units: [unichar]) {
        self.kind = kind
        self.units = units
    }

    private func at(_ offset: Int) -> unichar {
        offset < units.count ? units[offset] : 0
    }

    private mutating func emit(_ start: Int, _ end: Int, _ kind: TokenKind) {
        guard end > start else { return }
        if let last = tokens.last, last.end == start, last.kind == kind {
            tokens[tokens.count - 1] = Token(start: last.start, end: end, kind: kind)
        } else {
            tokens.append(Token(start: start, end: end, kind: kind))
        }
    }

    /// Lexes the line from `state` and returns the state at the start of the next line.
    mutating func run(from state: State) -> State {
        if kind == .xcconfig {
            xcconfig()
            return .normal
        }
        switch state {
        case .blockComment:
            if !blockComment(from: 0, continuing: true) { return .blockComment }
        case .string(let key):
            if !string(from: 0, key: key, continuing: true) { return .string(key: key) }
        case .normal:
            break
        }
        while index < units.count {
            let unit = units[index]
            if Self.isSpace(unit) {
                index += 1
            } else if unit == 0x2F, at(index + 1) == 0x2A {  // /*
                if !blockComment(from: index, continuing: false) { return .blockComment }
            } else if unit == 0x2F, at(index + 1) == 0x2F {  // //
                emit(index, lineContentEnd, .comment)
                index = units.count
            } else if unit == 0x22 {  // "
                let key = kind == .appleStrings ? !afterEquals : isFollowedByEquals(from: closingQuote(from: index + 1))
                if !string(from: index, key: key, continuing: false) { return .string(key: key) }
            } else if unit == 0x3D {  // =
                emit(index, index + 1, .operator)
                afterEquals = true
                index += 1
            } else if unit == 0x3B {  // ;
                emit(index, index + 1, .punctuation)
                afterEquals = false
                index += 1
            } else if "{}(),".utf16.contains(unit) {
                emit(index, index + 1, .punctuation)
                index += 1
            } else if Self.isWord(unit) {
                word()
            } else {
                index += 1
            }
        }
        return .normal
    }

    /// The end of the line without its line break.
    private var lineContentEnd: Int {
        var end = units.count
        while end > 0, units[end - 1] == 0x0A || units[end - 1] == 0x0D { end -= 1 }
        return end
    }

    /// Lexes a block comment opening at `start` (or continuing from the previous line); false when it runs past
    /// the line.
    private mutating func blockComment(from start: Int, continuing: Bool) -> Bool {
        var cursor = continuing ? start : start + 2
        while cursor < units.count {
            if units[cursor] == 0x2A, at(cursor + 1) == 0x2F {
                emit(start, cursor + 2, .comment)
                index = cursor + 2
                return true
            }
            cursor += 1
        }
        emit(start, units.count, .comment)
        index = units.count
        return false
    }

    private func closingQuote(from start: Int) -> Int {
        var cursor = start
        while cursor < units.count {
            if units[cursor] == 0x5C { cursor += 2; continue }
            if units[cursor] == 0x22 { return cursor + 1 }
            cursor += 1
        }
        return units.count
    }

    private func isFollowedByEquals(from start: Int) -> Bool {
        var cursor = start
        while cursor < units.count, Self.isSpace(units[cursor]) { cursor += 1 }
        return at(cursor) == 0x3D
    }

    /// Lexes a string opening at `start` (or continuing from the previous line); false when it runs past the
    /// line.
    private mutating func string(from start: Int, key: Bool, continuing: Bool) -> Bool {
        let kind: TokenKind = key ? .property : .string
        var cursor = continuing ? start : start + 1
        var runStart = start
        while cursor < units.count {
            let unit = units[cursor]
            if unit == 0x22 {
                emit(runStart, cursor + 1, kind)
                index = cursor + 1
                return true
            }
            if unit == 0x5C {  // escape: \n, \", \U1234
                emit(runStart, cursor, kind)
                var end = min(cursor + 2, units.count)
                if at(cursor + 1) == 0x55 || at(cursor + 1) == 0x75 {  // \U or \u + hex
                    while end < units.count, end < cursor + 6, Self.isHex(units[end]) { end += 1 }
                }
                emit(cursor, end, .stringSpecial)
                cursor = end
                runStart = cursor
                continue
            }
            if unit == 0x25, !key, let end = formatSpecifierEnd(from: cursor) {  // %@, %1$d, %.2f, %%
                emit(runStart, cursor, kind)
                emit(cursor, end, .stringSpecial)
                cursor = end
                runStart = cursor
                continue
            }
            cursor += 1
        }
        emit(runStart, units.count, kind)
        index = units.count
        return false
    }

    private func formatSpecifierEnd(from start: Int) -> Int? {
        var cursor = start + 1
        if at(cursor) == 0x25 { return cursor + 1 }
        while cursor < units.count, "0123456789$.-+# lhqLzjt".utf16.contains(units[cursor]) { cursor += 1 }
        guard cursor < units.count, "@dDiuUxXoOfFeEgGcCsSpaA".utf16.contains(units[cursor]) else { return nil }
        return cursor + 1
    }

    /// An unquoted word: keys before `=`, Xcode object ids, numbers, YES/NO and PBX/XC class names.
    private mutating func word() {
        let start = index
        while index < units.count, Self.isWord(units[index]) { index += 1 }
        let word = String(utf16CodeUnits: Array(units[start..<index]), count: index - start)
        let kind: TokenKind?
        if isFollowedByEquals(from: index) || (self.kind == .appleStrings && !afterEquals) {
            kind = .property
        } else if word.count == 24, word.utf16.allSatisfy(Self.isHex) {
            kind = .constant
        } else if word == "YES" || word == "NO" {
            kind = .constant
        } else if Double(word) != nil {
            kind = .number
        } else if word.hasPrefix("PBX") || word.hasPrefix("XC") {
            kind = .type
        } else {
            kind = nil
        }
        if let kind { emit(start, index, kind) }
    }

    // MARK: - .xcconfig

    private mutating func xcconfig() {
        let end = lineContentEnd
        while index < end, Self.isSpace(units[index]) { index += 1 }
        if at(index) == 0x2F, at(index + 1) == 0x2F {
            emit(index, end, .comment)
            return
        }
        if at(index) == 0x23 {  // #include, #include?
            let start = index
            while index < end, !Self.isSpace(units[index]), units[index] != 0x22 { index += 1 }
            emit(start, index, .keyword)
            xcconfigValue(to: end)
            return
        }
        // KEY[condition=value][…] = value
        let keyStart = index
        while index < end, Self.isIdentifier(units[index]) { index += 1 }
        emit(keyStart, index, .property)
        while index < end, units[index] == 0x5B {  // [
            let start = index
            while index < end, units[index] != 0x5D { index += 1 }
            index = min(end, index + 1)
            emit(start, index, .attribute)
        }
        while index < end, Self.isSpace(units[index]) { index += 1 }
        if at(index) == 0x3D {
            emit(index, index + 1, .operator)
            index += 1
        }
        xcconfigValue(to: end)
    }

    private mutating func xcconfigValue(to end: Int) {
        while index < end {
            let unit = units[index]
            if unit == 0x2F, at(index + 1) == 0x2F {
                emit(index, end, .comment)
                return
            }
            if unit == 0x22 {
                let close = min(closingQuote(from: index + 1), end)
                emit(index, close, .string)
                index = close
            } else if unit == 0x24, at(index + 1) == 0x28 || at(index + 1) == 0x7B {  // $( or ${
                let closer: unichar = at(index + 1) == 0x28 ? 0x29 : 0x7D
                let start = index
                var depth = 0
                while index < end {
                    if units[index] == 0x28 || units[index] == 0x7B { depth += 1 }
                    if units[index] == closer {
                        depth -= 1
                        if depth == 0 { break }
                    }
                    index += 1
                }
                index = min(end, index + 1)
                let reference = String(utf16CodeUnits: Array(units[start..<index]), count: index - start)
                emit(start, index, reference == "$(inherited)" || reference == "${inherited}" ? .variableBuiltin : .variable)
            } else if Self.isWord(unit) {
                let start = index
                while index < end, Self.isWord(units[index]) { index += 1 }
                let word = String(utf16CodeUnits: Array(units[start..<index]), count: index - start)
                if word == "YES" || word == "NO" {
                    emit(start, index, .constant)
                } else if Double(word) != nil {
                    emit(start, index, .number)
                }
            } else {
                index += 1
            }
        }
    }

    // MARK: - Characters

    private static func isSpace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }

    private static func isIdentifier(_ unit: unichar) -> Bool {
        (unit >= 0x30 && unit <= 0x39) || (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A) || unit == 0x5F
    }

    private static func isWord(_ unit: unichar) -> Bool {
        isIdentifier(unit) || unit == 0x2E || unit == 0x2D || unit == 0x24
    }

    private static func isHex(_ unit: unichar) -> Bool {
        (unit >= 0x30 && unit <= 0x39) || (unit >= 0x41 && unit <= 0x46) || (unit >= 0x61 && unit <= 0x66)
    }
}
