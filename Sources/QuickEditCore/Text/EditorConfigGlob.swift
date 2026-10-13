import Foundation

/// An EditorConfig glob compiled to an anchored regular expression, the way editorconfig-core does it. Numeric
/// ranges (`{1..3}`) become capture groups whose values are checked after the match.
struct EditorConfigGlob {
    let regex: NSRegularExpression
    let ranges: [ClosedRange<Int>]

    /// `path` is relative to the `.editorconfig` folder and starts with `/`.
    func matches(_ path: String) -> Bool {
        let nsPath = path as NSString
        guard let match = regex.firstMatch(in: path, range: NSRange(location: 0, length: nsPath.length)) else {
            return false
        }
        for (offset, range) in ranges.enumerated() {
            let capture = match.range(at: offset + 1)
            guard capture.location != NSNotFound else { continue }  // in an alternative that didn't match
            let captured = nsPath.substring(with: capture)
            let digits = captured.drop(while: { $0 == "+" || $0 == "-" })
            // Zero-padded numbers ("060") don't match a range, as in editorconfig-core.
            guard digits.count == 1 || digits.first != "0", let number = Int(captured), range.contains(number) else {
                return false
            }
        }
        return true
    }

    static func compile(_ glob: String) -> EditorConfigGlob? {
        // Without a slash the glob matches at any depth; with one it is anchored to the .editorconfig folder.
        let anchored = glob.contains("/") ? (glob.hasPrefix("/") ? glob : "/" + glob) : "/**/" + glob
        var translator = Translator(chars: Array(anchored.unicodeScalars))
        let body = translator.translate(0..<translator.chars.count)
        guard let regex = try? NSRegularExpression(pattern: "^" + body + "$") else { return nil }
        return EditorConfigGlob(regex: regex, ranges: translator.ranges)
    }

    private struct Translator {
        let chars: [Unicode.Scalar]
        var ranges: [ClosedRange<Int>] = []

        init(chars: [Unicode.Scalar]) { self.chars = chars }

        mutating func translate(_ range: Range<Int>) -> String {
            var pattern = ""
            var index = range.lowerBound
            let end = range.upperBound
            func char(_ offset: Int) -> Unicode.Scalar? { offset < end ? chars[offset] : nil }

            while index < end {
                let c = chars[index]
                switch c {
                case "\\":
                    if let next = char(index + 1) {
                        pattern += Self.literal(next)
                        index += 2
                    } else {
                        pattern += Self.literal(c)
                        index += 1
                    }
                case "*":
                    if char(index + 1) == "*" {
                        pattern += ".*"
                        while char(index) == "*" { index += 1 }
                    } else {
                        pattern += "[^/]*"
                        index += 1
                    }
                case "?":
                    pattern += "[^/]"
                    index += 1
                case "/":
                    if char(index + 1) == "*", char(index + 2) == "*", char(index + 3) == "/" {
                        pattern += "(?:/|/.*/)"  // "/**/" also matches a single slash: zero folders
                        index += 4
                    } else {
                        pattern += "/"
                        index += 1
                    }
                case "[":
                    if let (classPattern, next) = bracketClass(at: index, end: end) {
                        pattern += classPattern
                        index = next
                    } else {
                        pattern += Self.literal(c)
                        index += 1
                    }
                case "{":
                    if let (bracePattern, next) = braceGroup(at: index, end: end) {
                        pattern += bracePattern
                        index = next
                    } else {
                        pattern += Self.literal(c)
                        index += 1
                    }
                default:
                    pattern += Self.literal(c)
                    index += 1
                }
            }
            return pattern
        }

        /// `[abc]`, `[!abc]`, `[a-z]`. Unclosed classes, empty ones and classes containing `/` are literal.
        private func bracketClass(at start: Int, end: Int) -> (String, Int)? {
            var index = start + 1
            let negated = index < end && chars[index] == "!"
            if negated { index += 1 }
            let contentStart = index
            while index < end, chars[index] != "]" {
                if chars[index] == "/" { return nil }
                index += chars[index] == "\\" ? 2 : 1
            }
            guard index < end, index > contentStart else { return nil }
            var items = ""
            var cursor = contentStart
            while cursor < index {
                var c = chars[cursor]
                if c == "\\", cursor + 1 < index {
                    cursor += 1
                    c = chars[cursor]
                    items += Self.classLiteral(c)
                } else if c == "-", cursor > contentStart, cursor + 1 < index {
                    items += "-"
                } else {
                    items += Self.classLiteral(c)
                }
                cursor += 1
            }
            return ("[" + (negated ? "^" : "") + items + "]", index + 1)
        }

        /// `{a,b}` alternatives (nestable) and `{num1..num2}` ranges. A brace without a top-level comma (`{single}`,
        /// `{}`) or without its closing brace is literal.
        private mutating func braceGroup(at start: Int, end: Int) -> (String, Int)? {
            var depth = 0
            var index = start
            var close: Int?
            while index < end {
                switch chars[index] {
                case "\\": index += 1
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { close = index }
                default: break
                }
                if close != nil { break }
                index += 1
            }
            guard let close else { return nil }
            let content = String(String.UnicodeScalarView(chars[(start + 1)..<close]))
            if let range = Self.numericRange(content) {
                ranges.append(range)
                return ("([+-]?[0-9]+)", close + 1)
            }
            let parts = topLevelParts(start + 1, close)
            guard parts.count > 1 else { return nil }
            var alternatives: [String] = []
            for part in parts { alternatives.append(translate(part)) }
            return ("(?:" + alternatives.joined(separator: "|") + ")", close + 1)
        }

        private func topLevelParts(_ start: Int, _ end: Int) -> [Range<Int>] {
            var parts: [Range<Int>] = []
            var depth = 0
            var partStart = start
            var index = start
            while index < end {
                switch chars[index] {
                case "\\": index += 1
                case "{": depth += 1
                case "}": depth -= 1
                case "," where depth == 0:
                    parts.append(partStart..<index)
                    partStart = index + 1
                default: break
                }
                index += 1
            }
            parts.append(partStart..<end)
            return parts
        }

        private static func numericRange(_ content: String) -> ClosedRange<Int>? {
            let bounds = content.components(separatedBy: "..")
            guard bounds.count == 2,
                  bounds.allSatisfy({ !$0.isEmpty && $0.drop(while: { $0 == "+" || $0 == "-" }).allSatisfy(\.isASCIIDigit) }),
                  let low = Int(bounds[0]), let high = Int(bounds[1])
            else { return nil }
            return min(low, high)...max(low, high)
        }

        private static func literal(_ c: Unicode.Scalar) -> String {
            NSRegularExpression.escapedPattern(for: String(c))
        }

        private static func classLiteral(_ c: Unicode.Scalar) -> String {
            if c.isASCII, !c.properties.isAlphabetic, !("0"..."9").contains(c) { return "\\" + String(c) }
            return String(c)
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
