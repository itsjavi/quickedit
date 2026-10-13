import Foundation
import SwiftTreeSitter
import Synchronization

/// Why a vendored grammar couldn't be loaded.
enum GrammarError: Error, Sendable, CustomStringConvertible {
    case unknownGrammar(String)
    case query(grammar: String, kind: String, error: String)

    var description: String {
        switch self {
        case .unknownGrammar(let name): "unknown grammar '\(name)'"
        case .query(let grammar, let kind, let error): "\(grammar) \(kind) query: \(error)"
        }
    }
}

/// `#set!` settings of one injection query pattern.
struct InjectionPattern: Sendable {
    var language: String?
    var includeChildren = false
    var combined = false
}

/// A grammar with its compiled highlight and injection queries. Immutable and shared between highlighters.
final class GrammarConfiguration: Sendable {
    let name: String
    let language: SwiftTreeSitter.Language
    let highlights: Query?
    /// What each highlight capture paints, by capture index: nil for nothing, `CaptureCollector.clear` for
    /// `@none`, otherwise a `TokenKind.fixed` index.
    let highlightCodes: [Int16?]
    let injections: Query?
    let injectionContentCapture: Int?
    let injectionLanguageCapture: Int?
    /// Injection settings by pattern index.
    let injectionPatterns: [InjectionPattern]
    /// Predicates evaluated here (`#lua-match?`, `#has-ancestor?`, …) by pattern index.
    let highlightPredicates: [[CustomPredicate]]
    let injectionPredicates: [[CustomPredicate]]
    /// Fold rules by node symbol (see `FoldRules`).
    let foldRules: [Int: [FoldRules.Rule]]

    init(name: String) throws(GrammarError) {
        guard let pointer = VendoredGrammars.language(named: name) else { throw .unknownGrammar(name) }
        let language = SwiftTreeSitter.Language(pointer)
        self.name = name
        self.language = language

        if let source = VendoredGrammars.highlightsQuery(named: name) {
            let query = try Self.compile(source, language: language, grammar: name, kind: "highlights")
            highlights = query
            highlightPredicates = CustomPredicate.compile(query)
            highlightCodes = (0..<query.captureCount).map { index in
                switch query.captureName(for: index).flatMap(CaptureMapping.style(forCapture:)) {
                case nil: nil
                case .clear: CaptureCollector.clear
                case .token(let kind): TokenKind.paletteIndices[kind]
                }
            }
        } else {
            highlights = nil
            highlightCodes = []
            highlightPredicates = []
        }

        if let source = VendoredGrammars.injectionsQuery(named: name) {
            let query = try Self.compile(source, language: language, grammar: name, kind: "injections")
            injections = query
            let names = (0..<query.captureCount).map { query.captureName(for: $0) }
            injectionContentCapture = names.firstIndex(of: "injection.content")
            injectionLanguageCapture = names.firstIndex(of: "injection.language")
            injectionPatterns = (0..<query.patternCount).map { Self.injectionPattern(query.predicates(for: $0)) }
            injectionPredicates = CustomPredicate.compile(query)
        } else {
            injections = nil
            injectionContentCapture = nil
            injectionLanguageCapture = nil
            injectionPatterns = []
            injectionPredicates = []
        }

        foldRules = FoldRules.symbols(for: name, in: language)
    }

    private static func compile(
        _ source: String, language: SwiftTreeSitter.Language, grammar: String, kind: String
    ) throws(GrammarError) -> Query {
        do {
            return try Query(language: language, data: Data(source.utf8))
        } catch let error as QueryError {
            throw .query(grammar: grammar, kind: kind, error: describe(error, in: source))
        } catch {
            throw .query(grammar: grammar, kind: kind, error: "\(error)")
        }
    }

    /// The error with the offending line of the composed query, which is what you need to fix an override.
    private static func describe(_ error: QueryError, in source: String) -> String {
        let offset: UInt32
        switch error {
        case .none: return "unknown error"
        case .syntax(let o), .nodeType(let o), .field(let o), .capture(let o), .structure(let o), .unknown(let o):
            offset = o
        }
        let utf8 = Array(source.utf8)
        let position = min(Int(offset), utf8.count)
        let lineStart = utf8[..<position].lastIndex(of: 0x0A).map { $0 + 1 } ?? 0
        let lineEnd = utf8[position...].firstIndex(of: 0x0A) ?? utf8.count
        let line = String(decoding: utf8[lineStart..<lineEnd], as: UTF8.self)
        let lineNumber = utf8[..<position].reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
        return "\(error) at line \(lineNumber): \(line.trimmingCharacters(in: .whitespaces))"
    }

    private static func injectionPattern(_ predicates: [SwiftTreeSitter.Predicate]) -> InjectionPattern {
        var pattern = InjectionPattern()
        func apply(_ key: String, _ value: String?) {
            switch key {
            case "injection.language": pattern.language = value
            case "injection.include-children": pattern.includeChildren = true
            case "injection.combined": pattern.combined = true
            default: break
            }
        }
        for predicate in predicates {
            switch predicate {
            case .set(captureName: nil, key: let key, value: let value):
                apply(key, value)
            case .generic("set!", strings: let strings, captureNames: _) where !strings.isEmpty:
                apply(strings[0], strings.count > 1 ? strings[1] : nil)
            default:
                break
            }
        }
        return pattern
    }
}

/// Loads grammar configurations once per process (query compilation is the expensive part).
enum GrammarStore {
    private static let cache = Mutex<[String: Result<GrammarConfiguration, GrammarError>]>([:])

    static func configuration(named name: String) -> GrammarConfiguration? {
        try? load(name)
    }

    static func load(_ name: String) throws(GrammarError) -> GrammarConfiguration {
        if let cached = cache.withLock({ $0[name] }) {
            return try cached.get()
        }
        let result: Result<GrammarConfiguration, GrammarError>
        do {
            result = .success(try GrammarConfiguration(name: name))
        } catch {
            result = .failure(error)
        }
        cache.withLock { $0[name] = result }
        return try result.get()
    }

    /// The grammar for an injection language name: a grammar name ("markdown_inline") or anything
    /// `LanguageRegistry.language(forFenceInfo:)` understands ("ts", "sh", "yml").
    static func grammarName(forInjection name: String) -> String? {
        let key = name.lowercased()
        if VendoredGrammars.names.contains(key) {
            return key
        }
        switch LanguageRegistry.language(forFenceInfo: key)?.highlighting {
        case .grammar(let grammar): return grammar
        // Fenced Lumiose code gets its host grammar; its <style> blocks aren't split out there.
        case .styled(let host): return host
        default: return nil
        }
    }
}
