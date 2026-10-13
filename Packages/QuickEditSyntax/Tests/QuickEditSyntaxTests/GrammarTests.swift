import Foundation
import SwiftTreeSitter
import Testing

@testable import QuickEditSyntax

@Suite("Vendored grammars and embedded queries")
struct GrammarTests {
    @Test("every grammar loads and its queries compile", arguments: VendoredGrammars.names)
    func grammarLoads(name: String) throws {
        let grammar = try GrammarStore.load(name)
        #expect(grammar.language.ABIVersion >= SwiftTreeSitter.Language.minimumCompatibleVersion)
        #expect(grammar.language.ABIVersion <= SwiftTreeSitter.Language.version)
        let highlights = try #require(grammar.highlights, "\(name) has no highlights query")
        #expect(highlights.patternCount > 0)
        // At least one capture maps to a token kind.
        #expect(grammar.highlightCodes.contains { $0 != nil && $0 != CaptureCollector.clear })
        let ruleTypes = Set((FoldRules.rules[name] ?? []).map(\.type))
        let foundTypes = Set(grammar.foldRules.values.flatMap { $0.map(\.type) })
        #expect(ruleTypes == foundTypes, "\(name) fold rules name missing node types: \(ruleTypes.subtracting(foundTypes))")
        if let injections = grammar.injections {
            #expect(grammar.injectionContentCapture != nil, "\(name) injections lack @injection.content")
            #expect(injections.patternCount == grammar.injectionPatterns.count)
        }
    }

    @Test("every grammar a language uses is vendored")
    func languagesUseVendoredGrammars() {
        for language in LanguageRegistry.all {
            if case .grammar(let name) = language.highlighting {
                #expect(VendoredGrammars.names.contains(name), "\(language.id) uses missing grammar \(name)")
            }
        }
    }

    @Test("injection language names resolve to grammars")
    func injectionNames() {
        let expected = [
            "markdown_inline": "markdown_inline", "javascript": "javascript", "js": "javascript",
            "ts": "typescript", "typescript": "typescript", "tsx": "tsx", "css": "css", "html": "html",
            "yaml": "yaml", "yml": "yaml", "toml": "toml", "bash": "bash", "sh": "bash", "shell": "bash",
            "zsh": "bash", "json": "json", "jsonc": "json", "py": "python", "python": "python", "rust": "rust",
            "go": "go", "swift": "swift", "sql": "sql", "diff": "diff", "dockerfile": "dockerfile", "xml": "xml",
            "gdscript": "gdscript", "make": "make", "ini": "ini",
        ]
        for (name, grammar) in expected {
            #expect(GrammarStore.grammarName(forInjection: name) == grammar, "\(name)")
        }
        #expect(GrammarStore.grammarName(forInjection: "regex") == nil)
        #expect(GrammarStore.grammarName(forInjection: "jsdoc") == nil)
        #expect(GrammarStore.grammarName(forInjection: "csv") == nil)
    }

    @Test("capture names map to token kinds")
    func captureMapping() {
        let cases: [(String, CaptureStyle?)] = [
            ("keyword", .token(.keyword)),
            ("keyword.control.return", .token(.keyword)),
            ("keyword.operator", .token(.keyword)),
            ("conditional", .token(.keyword)),
            ("type.qualifier", .token(.keyword)),
            ("string", .token(.string)),
            ("string.escape", .token(.stringSpecial)),
            ("string.special.key", .token(.property)),
            ("string.special.url", .token(.link)),
            ("punctuation.special", .token(.stringSpecial)),
            ("punctuation.bracket", .token(.punctuation)),
            ("comment.documentation", .token(.comment)),
            ("number.float", .token(.number)),
            ("boolean", .token(.constant)),
            ("constant.builtin", .token(.constant)),
            ("function.method.call", .token(.function)),
            ("constructor", .token(.type)),
            ("type.builtin", .token(.type)),
            ("variable", .token(.variable)),
            ("variable.builtin", .token(.variableBuiltin)),
            ("variable.parameter", .token(.parameter)),
            ("variable.member", .token(.property)),
            ("module", .token(.namespace)),
            ("markup.heading.1", .token(.heading)),
            ("text.title", .token(.heading)),
            ("text.literal", .token(.codeSpan)),
            ("markup.list.checked", .token(.listMarker)),
            ("diff.plus", .token(.inserted)),
            ("diff.minus", .token(.deleted)),
            ("diff.delta", .token(.diffMeta)),
            ("tag.error", .token(.invalid)),
            ("none", .clear),
            ("embedded", nil),
            ("spell", nil),
            ("_name", nil),
            ("injection.content", nil),
            ("markup", nil),
            ("text", nil),
            ("error", nil),
            ("unknown.thing", nil),
        ]
        for (name, style) in cases {
            #expect(CaptureMapping.style(forCapture: name) == style, "\(name)")
        }
    }

    @Test("every capture name in the embedded queries is either mapped or deliberately ignored")
    func unmappedCaptures() throws {
        let ignored: Set<String> = [
            "embedded", "spell", "nospell", "markup", "error", "identifier.unused", "_target", "_name", "glimmer",
        ]
        var unmapped: [String] = []
        for name in VendoredGrammars.names {
            let grammar = try GrammarStore.load(name)
            guard let query = grammar.highlights else { continue }
            for index in 0..<query.captureCount {
                guard let capture = query.captureName(for: index), !ignored.contains(capture),
                    !capture.hasPrefix("_"), CaptureMapping.style(forCapture: capture) == nil
                else { continue }
                unmapped.append("\(name): @\(capture)")
            }
        }
        #expect(unmapped.isEmpty, "\(unmapped.joined(separator: "\n"))")
    }
}
