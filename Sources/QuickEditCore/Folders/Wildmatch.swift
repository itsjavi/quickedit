import Foundation

/// A port of git's `wildmatch()` with `WM_PATHNAME` (and optionally `WM_CASEFOLD`), the matcher behind `.gitignore`.
/// Works on UTF-8 bytes like git: `*` and `?` never match `/`, `**` between slashes matches any number of folders,
/// `[...]` classes support `!`/`^`, ranges, `\` escapes and `[:alpha:]`-style names.
enum Wildmatch {
    private enum Result { case match, noMatch, abortAll, abortToStarStar }

    static func matches(_ pattern: UnsafeBufferPointer<UInt8>, _ text: UnsafeBufferPointer<UInt8>, caseFold: Bool) -> Bool {
        match(pattern, 0, text, 0, caseFold) == .match
    }

    private static let slash = UInt8(ascii: "/")
    private static let star = UInt8(ascii: "*")
    private static let backslash = UInt8(ascii: "\\")

    @inline(__always) private static func fold(_ byte: UInt8, _ caseFold: Bool) -> UInt8 {
        caseFold && byte >= 0x41 && byte <= 0x5A ? byte | 0x20 : byte
    }

    private static func isGlobSpecial(_ byte: UInt8) -> Bool {
        byte == star || byte == UInt8(ascii: "?") || byte == UInt8(ascii: "[") || byte == backslash
    }

    private static func match(
        _ p: UnsafeBufferPointer<UInt8>, _ startP: Int, _ t: UnsafeBufferPointer<UInt8>, _ startT: Int, _ caseFold: Bool
    ) -> Result {
        var pi = startP, ti = startT
        while pi < p.count {
            var pCh = fold(p[pi], caseFold)
            if ti >= t.count, pCh != star { return .abortAll }
            let tCh = ti < t.count ? fold(t[ti], caseFold) : 0
            switch pCh {
            case backslash:
                // Literal match with the next character; a trailing backslash never matches.
                pi += 1
                guard pi < p.count, fold(p[pi], caseFold) == tCh else { return .noMatch }
            case UInt8(ascii: "?"):
                if tCh == slash { return .noMatch }
            case star:
                var matchSlash = false
                pi += 1
                if pi < p.count, p[pi] == star {
                    let previous = pi - 2
                    while pi < p.count, p[pi] == star { pi += 1 }
                    let atSegmentStart = previous < 0 || p[previous] == slash
                    let atSegmentEnd = pi == p.count || p[pi] == slash
                        || (p[pi] == backslash && pi + 1 < p.count && p[pi + 1] == slash)
                    if atSegmentStart, atSegmentEnd {
                        // "**/" may match no folder at all: try the rest right here first.
                        if pi < p.count, p[pi] == slash, match(p, pi + 1, t, ti, caseFold) == .match { return .match }
                        matchSlash = true
                    }
                }
                if pi == p.count {
                    // A trailing "**" matches everything; a trailing "*" only up to the next slash.
                    if !matchSlash, t[ti...].contains(slash) { return .noMatch }
                    return .match
                }
                if !matchSlash, p[pi] == slash {
                    // One "*" followed by a slash matches the rest of this path component.
                    guard let next = t[ti...].firstIndex(of: slash) else { return .noMatch }
                    ti = next
                    break  // the loop increment consumes both slashes
                }
                var current = tCh
                while ti < t.count {
                    current = fold(t[ti], caseFold)
                    if !isGlobSpecial(p[pi]) {
                        // Skip ahead to the next occurrence of the literal that follows the star.
                        let literal = fold(p[pi], caseFold)
                        while ti < t.count {
                            current = fold(t[ti], caseFold)
                            if current == literal || (!matchSlash && current == slash) { break }
                            ti += 1
                        }
                        if ti >= t.count || current != literal { return .noMatch }
                    }
                    let result = match(p, pi, t, ti, caseFold)
                    if result != .noMatch {
                        if !matchSlash || result != .abortToStarStar { return result }
                    } else if !matchSlash, current == slash {
                        return .abortToStarStar
                    }
                    ti += 1
                }
                return .abortAll
            case UInt8(ascii: "["):
                pi += 1
                guard pi < p.count else { return .abortAll }
                pCh = p[pi]
                if pCh == UInt8(ascii: "^") { pCh = UInt8(ascii: "!") }
                let negated = pCh == UInt8(ascii: "!")
                if negated {
                    pi += 1
                    guard pi < p.count else { return .abortAll }
                    pCh = p[pi]
                }
                var previous: UInt8 = 0
                var matched = false
                repeat {
                    pCh = p[pi]
                    if pCh == backslash {
                        pi += 1
                        guard pi < p.count else { return .abortAll }
                        if tCh == fold(p[pi], caseFold) { matched = true }
                        previous = p[pi]
                    } else if pCh == UInt8(ascii: "-"), previous != 0, pi + 1 < p.count, p[pi + 1] != UInt8(ascii: "]") {
                        pi += 1
                        var upper = p[pi]
                        if upper == backslash {
                            pi += 1
                            guard pi < p.count else { return .abortAll }
                            upper = p[pi]
                        }
                        if tCh <= upper, tCh >= previous {
                            matched = true
                        } else if caseFold, tCh >= 0x61, tCh <= 0x7A {
                            let tUpper = tCh - 0x20
                            if tUpper <= upper, tUpper >= previous { matched = true }
                        }
                        previous = 0
                    } else if pCh == UInt8(ascii: "["), pi + 1 < p.count, p[pi + 1] == UInt8(ascii: ":") {
                        let nameStart = pi + 2
                        var end = nameStart
                        while end < p.count, p[end] != UInt8(ascii: "]") { end += 1 }
                        guard end < p.count else { return .abortAll }
                        if end - 1 < nameStart || p[end - 1] != UInt8(ascii: ":") {
                            // Not "[:name:]": a literal "[".
                            if tCh == UInt8(ascii: "[") { matched = true }
                            previous = UInt8(ascii: "[")
                        } else {
                            let name = String(decoding: UnsafeBufferPointer(rebasing: p[nameStart..<(end - 1)]), as: UTF8.self)
                            guard let test = posixClass(name, caseFold: caseFold) else { return .abortAll }
                            if test(tCh) { matched = true }
                            pi = end
                            previous = 0
                        }
                    } else {
                        if tCh == fold(pCh, caseFold) { matched = true }
                        previous = pCh
                    }
                    pi += 1
                    guard pi < p.count else { return .abortAll }
                } while p[pi] != UInt8(ascii: "]")
                if matched == negated || tCh == slash { return .noMatch }
            default:
                if tCh != pCh { return .noMatch }
            }
            pi += 1
            ti += 1
        }
        return ti >= t.count ? .match : .noMatch
    }

    private static func posixClass(_ name: String, caseFold: Bool) -> ((UInt8) -> Bool)? {
        func isUpper(_ c: UInt8) -> Bool { c >= 0x41 && c <= 0x5A }
        func isLower(_ c: UInt8) -> Bool { c >= 0x61 && c <= 0x7A }
        func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }
        func isAlpha(_ c: UInt8) -> Bool { isUpper(c) || isLower(c) }
        func isPrint(_ c: UInt8) -> Bool { c >= 0x20 && c < 0x7F }
        switch name {
        case "alnum": return { isAlpha($0) || isDigit($0) }
        case "alpha": return isAlpha
        case "blank": return { $0 == 0x20 || $0 == 0x09 }
        case "cntrl": return { $0 < 0x20 || $0 == 0x7F }
        case "digit": return isDigit
        case "graph": return { isPrint($0) && $0 != 0x20 }
        case "lower": return caseFold ? isAlpha : isLower
        case "print": return isPrint
        case "punct": return { isPrint($0) && $0 != 0x20 && !isAlpha($0) && !isDigit($0) }
        case "space": return { $0 == 0x20 || ($0 >= 0x09 && $0 <= 0x0D) }
        case "upper": return caseFold ? isAlpha : isUpper
        case "xdigit": return { isDigit($0) || ($0 >= 0x41 && $0 <= 0x46) || ($0 >= 0x61 && $0 <= 0x66) }
        default: return nil
        }
    }
}
