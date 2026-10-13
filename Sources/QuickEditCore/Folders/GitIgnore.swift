import Foundation

/// The rules of one `.gitignore` (or `.git/info/exclude`) file, with git's semantics: blank lines and `#` comments are
/// skipped, unescaped trailing spaces are dropped, `!` re-includes, a trailing `/` matches only folders, a pattern with
/// a `/` at the start or in the middle is relative to the file's folder (otherwise it matches a name at any depth),
/// and the last matching rule wins.
public struct GitIgnore: Sendable {
    /// The folder holding the file, relative to the repository (or opened folder) root; "" for the root itself.
    public let base: String
    let rules: [Rule]
    let ignoreCase: Bool

    struct Rule: Sendable {
        let pattern: [UInt8]
        let negated: Bool
        let directoryOnly: Bool
        /// No slash in the pattern: it matches the last path component at any depth.
        let matchesName: Bool
        let literal: Bool
        /// "*suffix" with no other wildcards, matched as a plain suffix of the name.
        let suffix: [UInt8]?
    }

    /// `ignoreCase` mirrors git's `core.ignorecase` (true in most repositories created on macOS).
    public init(contents: String, base: String, ignoreCase: Bool = false) {
        self.base = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.ignoreCase = ignoreCase
        var rules: [Rule] = []
        for line in contents.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            if let rule = Self.parse(Array(line.utf8), ignoreCase: ignoreCase) { rules.append(rule) }
        }
        self.rules = rules
    }

    public var isEmpty: Bool { rules.isEmpty }

    /// git's `wildmatch` with `WM_PATHNAME`: matches a whole glob against a whole `/`-separated path, with no
    /// `.gitignore` line processing.
    public static func matches(pattern: String, path: String, ignoreCase: Bool = false) -> Bool {
        var pattern = pattern, path = path
        return pattern.withUTF8 { p in path.withUTF8 { Wildmatch.matches(p, $0, caseFold: ignoreCase) } }
    }

    /// Whether the last rule matching `relativePath` (relative to the same root as `base`) ignores it; nil when no
    /// rule matches or the path is outside `base`. Only the path itself is tested: a file inside an ignored folder is
    /// reported by `IgnoreRules`, which also checks the folders above it.
    public func isIgnored(_ relativePath: String, isDirectory: Bool) -> Bool? {
        var path = relativePath
        return path.withUTF8 { isIgnored(pathBytes: $0, isDirectory: isDirectory) }
    }

    func isIgnored(pathBytes: UnsafeBufferPointer<UInt8>, isDirectory: Bool) -> Bool? {
        guard !rules.isEmpty else { return nil }
        var start = 0
        if !base.isEmpty {
            let baseCount = base.utf8.count
            guard pathBytes.count > baseCount + 1, pathBytes[baseCount] == UInt8(ascii: "/"),
                  base.utf8.elementsEqual(pathBytes[0..<baseCount])
            else { return nil }
            start = baseCount + 1
        }
        let path = UnsafeBufferPointer(rebasing: pathBytes[start...])
        var nameStart = path.count
        while nameStart > 0, path[nameStart - 1] != UInt8(ascii: "/") { nameStart -= 1 }
        let name = UnsafeBufferPointer(rebasing: path[nameStart...])

        for rule in rules.reversed() {
            if rule.directoryOnly, !isDirectory { continue }
            let subject = rule.matchesName ? name : path
            if Self.matches(rule, subject, ignoreCase: ignoreCase) { return !rule.negated }
        }
        return nil
    }

    // MARK: - Parsing and matching

    static func parse(_ raw: [UInt8], ignoreCase: Bool) -> Rule? {
        var line = raw
        if line.last == UInt8(ascii: "\r") { line.removeLast() }
        guard let first = line.first, first != UInt8(ascii: "#") else { return nil }
        trimTrailingSpaces(&line)
        var negated = false
        if line.first == UInt8(ascii: "!") {
            negated = true
            line.removeFirst()
        }
        var directoryOnly = false
        if line.last == UInt8(ascii: "/") {
            directoryOnly = true
            line.removeLast()
        }
        guard !line.isEmpty else { return nil }
        let matchesName = !line.contains(UInt8(ascii: "/"))
        if line.first == UInt8(ascii: "/") { line.removeFirst() }
        guard !line.isEmpty else { return nil }

        let specials: Set<UInt8> = [UInt8(ascii: "*"), UInt8(ascii: "?"), UInt8(ascii: "["), UInt8(ascii: "\\")]
        let literal = !line.contains(where: specials.contains)
        var suffix: [UInt8]?
        if matchesName, line.first == UInt8(ascii: "*"), !line.dropFirst().contains(where: specials.contains) {
            suffix = Array(line.dropFirst())
        }
        if ignoreCase {
            line = line.map { $0 >= 0x41 && $0 <= 0x5A ? $0 | 0x20 : $0 }
            suffix = suffix?.map { $0 >= 0x41 && $0 <= 0x5A ? $0 | 0x20 : $0 }
        }
        return Rule(
            pattern: line, negated: negated, directoryOnly: directoryOnly, matchesName: matchesName, literal: literal,
            suffix: suffix)
    }

    /// git's `trim_trailing_spaces`: drops trailing spaces unless the last one is escaped with a backslash.
    static func trimTrailingSpaces(_ line: inout [UInt8]) {
        var lastSpace: Int?
        var index = 0
        while index < line.count {
            switch line[index] {
            case UInt8(ascii: " "):
                if lastSpace == nil { lastSpace = index }
            case UInt8(ascii: "\\"):
                index += 1
                if index == line.count { return }
                lastSpace = nil
            default:
                lastSpace = nil
            }
            index += 1
        }
        if let lastSpace { line.removeSubrange(lastSpace...) }
    }

    static func matches(_ rule: Rule, _ subject: UnsafeBufferPointer<UInt8>, ignoreCase: Bool) -> Bool {
        @inline(__always) func fold(_ byte: UInt8) -> UInt8 {
            ignoreCase && byte >= 0x41 && byte <= 0x5A ? byte | 0x20 : byte
        }
        if rule.literal {
            guard subject.count == rule.pattern.count else { return false }
            for index in 0..<subject.count where fold(subject[index]) != rule.pattern[index] { return false }
            return true
        }
        if let suffix = rule.suffix {
            guard subject.count >= suffix.count else { return false }
            let offset = subject.count - suffix.count
            for index in 0..<suffix.count where fold(subject[offset + index]) != suffix[index] { return false }
            return true
        }
        return rule.pattern.withUnsafeBufferPointer { Wildmatch.matches($0, subject, caseFold: ignoreCase) }
    }
}
