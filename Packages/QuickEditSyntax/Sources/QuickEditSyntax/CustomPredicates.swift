import Foundation
import SwiftTreeSitter

/// Query predicates SwiftTreeSitter doesn't evaluate (it lets every unknown predicate pass), taken from
/// Neovim's set so upstream queries written for it behave: `#lua-match?` (Lua patterns), `#has-ancestor?` and
/// `#has-parent?`, with their `not-` forms. Any other unknown `…?` predicate rejects its match rather than
/// highlighting more than the query meant.
enum CustomPredicate: Sendable {
    case match(NSRegularExpression, capture: String, negated: Bool)
    case ancestor(Set<String>, capture: String, negated: Bool, parentOnly: Bool)
    case never

    /// The custom predicates of each pattern of `query`.
    static func compile(_ query: Query) -> [[CustomPredicate]] {
        (0..<query.patternCount).map { pattern in
            query.predicates(for: pattern).compactMap { predicate in
                guard case .generic(let name, let strings, let captures) = predicate, name.hasSuffix("?") else {
                    return nil
                }
                let negated = name.hasPrefix("not-")
                let base = negated ? String(name.dropFirst(4)) : name
                switch base {
                case "lua-match?":
                    guard let capture = captures.first, let pattern = strings.first,
                        let regex = try? NSRegularExpression(pattern: LuaPattern.regex(from: pattern))
                    else { return .never }
                    return .match(regex, capture: capture, negated: negated)
                case "has-ancestor?", "has-parent?":
                    guard let capture = captures.first, !strings.isEmpty else { return .never }
                    return .ancestor(
                        Set(strings), capture: capture, negated: negated, parentOnly: base == "has-parent?")
                default:
                    return .never
                }
            }
        }
    }

    /// Whether `match` passes every predicate; `text` reads a node's text.
    static func allow(_ predicates: [CustomPredicate], _ match: QueryMatch, text: (NSRange) -> String?) -> Bool {
        predicates.allSatisfy { predicate in
            switch predicate {
            case .never:
                return false
            case .match(let regex, let capture, let negated):
                return match.captures(named: capture).allSatisfy { found in
                    guard let value = text(found.node.range) else { return false }
                    let matched = regex.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) != nil
                    return matched != negated
                }
            case .ancestor(let types, let capture, let negated, let parentOnly):
                return match.captures(named: capture).allSatisfy { found in
                    var node = found.node.parent
                    var found = false
                    while let current = node {
                        if let type = current.nodeType, types.contains(type) {
                            found = true
                            break
                        }
                        if parentOnly { break }
                        node = current.parent
                    }
                    return found != negated
                }
            }
        }
    }
}

/// Converts the Lua patterns Neovim queries use (`^[%u@][%u%d_]+$`, `^//!`) to ICU regular expressions.
enum LuaPattern {
    static func regex(from lua: String) -> String {
        var result = ""
        var inSet = false
        let characters = Array(lua)
        var index = 0
        func classBody(_ letter: Character) -> String? {
            switch letter {
            case "a": "A-Za-z"
            case "d": "0-9"
            case "l": "a-z"
            case "u": "A-Z"
            case "w": "A-Za-z0-9"
            case "x": "0-9A-Fa-f"
            case "s": "\\s"
            case "p": "\\p{P}\\p{S}"
            case "c": "\\p{Cc}"
            default: nil
            }
        }
        while index < characters.count {
            let character = characters[index]
            if character == "%", index + 1 < characters.count {
                let next = characters[index + 1]
                index += 2
                if let body = classBody(Character(next.lowercased())) {
                    let negated = next.isUppercase
                    if inSet {
                        // A negated class inside a set has no exact ICU spelling; approximate with the class.
                        result += body
                    } else {
                        result += negated ? "[^\(body)]" : "[\(body)]"
                    }
                } else {
                    // An escaped literal (`%.`, `%%`, `%-`).
                    result += NSRegularExpression.escapedPattern(for: String(next))
                }
                continue
            }
            switch character {
            case "[":
                inSet = true
                result.append(character)
            case "]":
                inSet = false
                result.append(character)
            case "-" where !inSet:
                result += "*?"  // Lua's lazy repetition
            default:
                if !inSet, "\\{}|/".contains(character) {
                    result += NSRegularExpression.escapedPattern(for: String(character))
                } else {
                    result.append(character)
                }
            }
            index += 1
        }
        return result
    }
}
