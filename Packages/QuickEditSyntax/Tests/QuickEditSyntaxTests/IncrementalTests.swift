import Foundation
import Testing

@testable import QuickEditSyntax

@Suite("Incremental edits")
struct IncrementalTests {
    struct Document: Sendable, CustomTestStringConvertible {
        let language: String
        let source: String
        /// Snippets typed at random positions.
        let snippets: [String]
        var testDescription: String { language }
    }

    static let documents: [Document] = [
        Document(
            language: "typescript",
            source: """
                import { readFile } from "node:fs/promises";

                /** Doc comment. */
                export interface Config { name: string; retries?: number }

                const DEFAULT_RETRIES = 3;

                export async function load(path: string): Promise<Config> {
                  const text = await readFile(path, "utf8");
                  const value = JSON.parse(text) as Config;
                  return { ...value, retries: value.retries ?? DEFAULT_RETRIES };
                }

                class Cache<T> extends Map<string, T> {
                  get size2() { return this.size * 2; }
                }
                // trailing comment
                """,
            snippets: [
                "x", " ", "\n", "const ", "\"", "'", "`${a}`", "/*", "*/", "{", "}", "(", ")", ";", "// note\n", "42",
                "if (a) {", "😀", "<T>", "=>",
            ]),
        Document(
            language: "markdown",
            source: """
                # Title with *emphasis*

                Paragraph with `code`, **bold** and a [link](https://example.com).

                ```ts
                const answer: number = 42;
                function f() { return answer; }
                ```

                > Quote with `code`
                > - nested list

                - item one
                - item `two`

                ```python
                def g(): return None
                ```

                Final paragraph.
                """,
            snippets: [
                "x", " ", "\n", "*", "**", "`", "```", "```js\n", "#", "> ", "- ", "[", "](", ")", "\n\n", "ts", "py",
                "<div>", "😀",
            ]),
        Document(
            language: "html",
            source: """
                <!DOCTYPE html>
                <html>
                <head>
                  <style>body { color: red; } .a > b { margin: 0 }</style>
                  <script>const x = 1; function f(a) { return a * x; }</script>
                </head>
                <body class="main"><p>Hello &amp; welcome</p></body>
                </html>
                """,
            snippets: ["x", " ", "\n", "<", ">", "</script>", "<script>", "\"", "{", "}", "/*", "*/", "<!--", "-->"]),
        Document(
            language: "python",
            source: """
                import os

                class Greeter:
                    \"\"\"Says hello.\"\"\"

                    def __init__(self, name: str) -> None:
                        self.name = name

                    def greet(self) -> str:
                        if self.name:
                            return f"Hello {self.name}!"
                        return "Hello"

                print(Greeter(os.getenv("USER", "world")).greet())
                """,
            snippets: ["x", " ", "\n", "    ", "\"", "'''", "#", "(", ")", ":", "def h():\n    pass\n", "\t"]),
        Document(
            language: "yaml",
            source: """
                name: ci
                on:
                  push:
                    branches: [main]
                jobs:
                  build:
                    runs-on: macos-26
                    steps:
                      - uses: actions/checkout@v4
                      - run: |
                          swift build
                          swift test
                """,
            snippets: ["x", " ", "\n", "  ", "- ", ": ", "\"", "#", "[", "]", "{", "}", "|\n"]),
        Document(
            language: "stsx",
            source: LumioseTests.postCard + LumioseTests.nested,
            snippets: [
                "x", " ", "\n", "<style>", "</style>", "<style global>", "<style", "</", "$theme.a", "$", ".", "{", "}",
                "`", "'", "\"", "//", "/*", "*/", "${", "<div>", "</div>",
            ]),
        Document(
            language: "sjsx",
            source: LumioseTests.counter + LumioseTests.layout.replacingOccurrences(of: "import type { LayoutProps } from \"lumiose\";\n", with: ""),
            snippets: ["x", " ", "\n", "<style>", "</style>", "$accent", "{", "}", "'", "\"", "/*", "*/", "<p>"]),
        Document(
            language: "cpp",
            source: MoreLanguagesTests.fixtures.first { $0.language == "cpp" }!.source,
            snippets: ["x", " ", "\n", "{", "}", "<", ">", "::", "\"", "/*", "*/", "//", "template <typename T>", ";"]),
        Document(
            language: "ruby",
            source: MoreLanguagesTests.fixtures.first { $0.language == "ruby" }!.source,
            snippets: ["x", " ", "\n", "end", "def a\n", "do |x|", "\"", "#{", "}", "#", ":sym", "  "]),
        Document(
            language: "php",
            source: MoreLanguagesTests.fixtures.first { $0.language == "php" }!.source,
            snippets: ["x", " ", "\n", "<?php", "?>", "$a", "{", "}", "'", "\"", "<p>", "/*", "*/"]),
        Document(
            language: "vue",
            source: MoreLanguagesTests.fixtures.first { $0.language == "vue" }!.source,
            snippets: ["x", " ", "\n", "<script>", "</script>", "{{", "}}", "<div>", "</div>", "\"", ":a=", "@click="]),
        Document(
            language: "strings",
            source: "/* Header */\n\"a\" = \"b %@\";\n// note\n\"c\" = \"d\\n\";\nkey = \"e\";\n",
            snippets: ["x", " ", "\n", "\"", "/*", "*/", "//", "=", ";", "%d", "\\"]),
        Document(
            language: "csv",
            source: "a,b,c\n1,\"x, y\",3\n4,5,6\n",
            snippets: ["x", ",", "\"", "\n", "\"\""]),
    ]

    @Test("random edits give the same tokens as a fresh parse, and the reported ranges cover every change",
        arguments: documents)
    func randomEdits(document: Document) {
        let language = LanguageRegistry.language(id: document.language)!
        var generator = SeededGenerator(seed: UInt64(document.language.utf8.reduce(7) { $0 &* 31 &+ UInt64($1) }))
        let highlighter = SyntaxHighlighter(language: language)
        var text = document.source as NSString
        highlighter.setText(text)
        var oldKinds = Self.kindsPerUnit(highlighter, text)

        // A second highlighter only ever sees small windows, like an editor scrolled somewhere, so injected layers
        // are created lazily and must stay correct across edits they didn't see.
        let windowed = SyntaxHighlighter(language: language)
        windowed.setText(text)

        for step in 0..<400 {
            let length = text.length
            let location = Int.random(in: 0...length, using: &generator)
            let deleteLength: Int
            let insertion: String
            switch Int.random(in: 0..<10, using: &generator) {
            case 0..<5:
                deleteLength = 0
                insertion = document.snippets.randomElement(using: &generator)!
            case 5..<8:
                deleteLength = Int.random(in: 0...min(12, length - location), using: &generator)
                insertion = ""
            default:
                deleteLength = Int.random(in: 0...min(6, length - location), using: &generator)
                insertion = document.snippets.randomElement(using: &generator)!
            }
            var range = NSRange(location: location, length: deleteLength)
            // Never split a surrogate pair.
            range = (text as NSString).rangeOfComposedCharacterSequences(for: range)
            if range.length == 0, range.location < text.length {
                range = NSRange(location: text.rangeOfComposedCharacterSequence(at: range.location).location, length: 0)
            }
            let mutable = NSMutableString(string: text)
            mutable.replaceCharacters(in: range, with: insertion)
            let newText = mutable.copy() as! NSString
            let insertedLength = (insertion as NSString).length
            let changed = highlighter.applyEdit(replacing: range, with: insertedLength, in: newText)
            windowed.applyEdit(replacing: range, with: insertedLength, in: newText)

            let incremental = highlighter.tokens(in: NSRange(location: 0, length: newText.length))
            let fresh = SyntaxHighlighter(language: language)
            fresh.setText(newText)
            let expected = fresh.tokens(in: NSRange(location: 0, length: newText.length))
            let windowStart = Int.random(in: 0...newText.length, using: &generator)
            let window = NSRange(location: windowStart, length: min(120, newText.length - windowStart))
            if windowed.tokens(in: window) != fresh.tokens(in: window) {
                Issue.record("\(document.language) step \(step): windowed tokens differ in \(window) after replacing \(range) with \(insertion.debugDescription)\n\(newText)")
                return
            }
            if highlighter.foldRanges() != fresh.foldRanges() {
                Issue.record("\(document.language) step \(step): incremental folds differ after replacing \(range) with \(insertion.debugDescription)\n\(newText)")
                return
            }
            if incremental != expected {
                Issue.record("\(document.language) step \(step): incremental tokens differ after replacing \(range) with \(insertion.debugDescription)\n\(newText)")
                return
            }

            // Outside the reported ranges (and the inserted text), every unit keeps its kind.
            let newKinds = Self.kindsPerUnit(highlighter, newText)
            let delta = insertedLength - range.length
            var covered = IndexSet()
            for range in changed { covered.insert(integersIn: range.location..<range.upperBound) }
            covered.insert(integersIn: range.location..<(range.location + insertedLength))
            for index in 0..<newText.length where !covered.contains(index) {
                let oldIndex = index < range.location ? index : index - delta
                if oldIndex < 0 || oldIndex >= oldKinds.count || oldKinds[oldIndex] != newKinds[index] {
                    let context = newText.substring(with: NSRange(location: max(0, index - 20), length: min(40, newText.length - max(0, index - 20))))
                    Issue.record("\(document.language) step \(step): unit \(index) changed kind (\(String(describing: oldIndex >= 0 && oldIndex < oldKinds.count ? oldKinds[oldIndex] : nil)) → \(String(describing: newKinds[index]))) outside the reported ranges \(changed) after replacing \(range) with \(insertion.debugDescription); around: \(context.debugDescription)\nold: \(text.debugDescription)\nnew: \(newText.debugDescription)")
                    return
                }
            }
            text = newText
            oldKinds = newKinds
        }
    }

    /// The editor defers slow reparses until typing pauses: edits then only adjust the tree, queries in between
    /// read the edited tree, and the catch-up parse must land exactly where parsing after every edit would.
    @Test("deferred reparses catch up with a fresh parse", arguments: documents)
    func deferredEdits(document: Document) {
        let language = LanguageRegistry.language(id: document.language)!
        var generator = SeededGenerator(seed: UInt64(document.language.utf8.reduce(11) { $0 &* 31 &+ UInt64($1) }))
        let highlighter = SyntaxHighlighter(language: language)
        highlighter.deferredParseThreshold = .zero  // defer every edit
        var text = document.source as NSString
        highlighter.setText(text)
        for step in 0..<200 {
            let location = Int.random(in: 0...text.length, using: &generator)
            var range = NSRange(location: location, length: Int.random(in: 0...min(4, text.length - location), using: &generator))
            range = text.rangeOfComposedCharacterSequences(for: range)
            if range.length == 0, range.location < text.length {
                range = NSRange(location: text.rangeOfComposedCharacterSequence(at: range.location).location, length: 0)
            }
            let insertion = Bool.random(using: &generator) ? document.snippets.randomElement(using: &generator)! : ""
            let mutable = NSMutableString(string: text)
            mutable.replaceCharacters(in: range, with: insertion)
            text = mutable.copy() as! NSString
            highlighter.applyEdit(replacing: range, with: (insertion as NSString).length, in: text)
            // Typing on: a query on the edited, not yet reparsed tree must not trip over it.
            _ = highlighter.tokens(in: NSRange(location: 0, length: text.length))
            // Pauses now and then, as typing does.
            guard step % 3 == 2 else { continue }
            highlighter.parsePending()
            #expect(!highlighter.hasPendingParse)
            let fresh = SyntaxHighlighter(language: language)
            fresh.setText(text)
            let all = NSRange(location: 0, length: text.length)
            let (tokens, expected) = (highlighter.tokens(in: all), fresh.tokens(in: all))
            guard tokens == expected, highlighter.foldRanges() == fresh.foldRanges() else {
                let mismatch = zip(tokens, expected).first { $0 != $1 }.map { "\($0.0) vs \($0.1)" } ?? "\(tokens.count) vs \(expected.count) tokens"
                Issue.record("\(document.language) step \(step): differs from a fresh parse (\(tokens == expected ? "folds" : mismatch)) after replacing \(range) with \(insertion.debugDescription)\n\(text)")
                return
            }
        }
    }

    /// The editor's catch-up: the reparse runs on a snapshot off the main thread while typing goes on, and the edits
    /// made meanwhile are replayed onto its tree. The job only reads copies, so running it after those edits is
    /// equivalent to running it during them (`concurrentBackgroundParse` overlaps them for real).
    @Test("background reparses catch up with a fresh parse, replaying the edits made meanwhile", arguments: documents)
    func backgroundDeferredEdits(document: Document) async {
        let language = LanguageRegistry.language(id: document.language)!
        var generator = SeededGenerator(seed: UInt64(document.language.utf8.reduce(17) { $0 &* 31 &+ UInt64($1) }))
        let highlighter = SyntaxHighlighter(language: language)
        highlighter.deferredParseThreshold = .zero  // defer every edit
        var text = document.source as NSString
        highlighter.setText(text)
        func edit() {
            let location = Int.random(in: 0...text.length, using: &generator)
            var range = NSRange(location: location, length: Int.random(in: 0...min(4, text.length - location), using: &generator))
            range = text.rangeOfComposedCharacterSequences(for: range)
            if range.length == 0, range.location < text.length {
                range = NSRange(location: text.rangeOfComposedCharacterSequence(at: range.location).location, length: 0)
            }
            let insertion = Bool.random(using: &generator) ? document.snippets.randomElement(using: &generator)! : ""
            let mutable = NSMutableString(string: text)
            mutable.replaceCharacters(in: range, with: insertion)
            text = mutable.copy() as! NSString
            highlighter.applyEdit(replacing: range, with: (insertion as NSString).length, in: text)
            _ = highlighter.tokens(in: NSRange(location: 0, length: text.length))
        }
        for step in 0..<120 {
            edit()
            guard step % 3 == 2, let job = highlighter.beginPendingParse() else { continue }  // nil: no tree-sitter
            let during = Int.random(in: 0...3, using: &generator)
            for _ in 0..<during { edit() }
            let result = await Task.detached { job.run() }.value
            #expect(highlighter.finishPendingParse(result) != nil)
            #expect(highlighter.hasPendingParse == (during > 0))
            highlighter.parsePending()
            let fresh = SyntaxHighlighter(language: language)
            fresh.setText(text)
            let all = NSRange(location: 0, length: text.length)
            let (tokens, expected) = (highlighter.tokens(in: all), fresh.tokens(in: all))
            guard tokens == expected, highlighter.foldRanges() == fresh.foldRanges() else {
                let mismatch = zip(tokens, expected).first { $0 != $1 }.map { "\($0.0) vs \($0.1)" } ?? "\(tokens.count) vs \(expected.count) tokens"
                Issue.record("\(document.language) step \(step), \(during) edits during the parse: differs from a fresh parse (\(tokens == expected ? "folds" : mismatch))\n\(text)")
                return
            }
        }
    }

    /// The first incremental parse after a full one can cost nearly as much (Markdown), so a slow full parse leaves
    /// a warm-up reparse for the editor to run in the background before the first keystroke (TASK-51).
    @Test("a full parse slower than the deferral threshold leaves a warm-up reparse waiting")
    func warmUpAfterSlowFullParse() {
        let markdown = LanguageRegistry.language(id: "markdown")!
        var text = "# Title\n\nSome *text* and `code`.\n" as NSString
        let fast = SyntaxHighlighter(language: markdown)
        fast.deferredParseThreshold = .seconds(10)
        fast.setText(text)
        #expect(!fast.hasPendingParse)
        let undeferred = SyntaxHighlighter(language: markdown)
        undeferred.setText(text)
        #expect(!undeferred.hasPendingParse)

        let slow = SyntaxHighlighter(language: markdown)
        slow.deferredParseThreshold = .zero  // every full parse counts as slow
        slow.setText(text)
        #expect(slow.hasPendingParse)
        // The first edit defers too; the warm-up and the edit catch up together.
        let mutable = NSMutableString(string: text)
        mutable.insert("x", at: 2)
        text = mutable.copy() as! NSString
        slow.applyEdit(replacing: NSRange(location: 2, length: 0), with: 1, in: text)
        #expect(slow.hasPendingParse)
        slow.parsePending()
        #expect(!slow.hasPendingParse)
        let fresh = SyntaxHighlighter(language: markdown)
        fresh.setText(text)
        let all = NSRange(location: 0, length: text.length)
        #expect(slow.tokens(in: all) == fresh.tokens(in: all))
    }

    @Test("a background reparse superseded by setText or a newer one is ignored")
    func staleBackgroundParse() {
        let markdown = LanguageRegistry.language(id: "markdown")!
        let highlighter = SyntaxHighlighter(language: markdown)
        highlighter.deferredParseThreshold = .zero
        var text = "# Title\n\nSome *text* and `code`.\n" as NSString
        highlighter.setText(text)
        func insert(_ string: String, at location: Int) {
            let mutable = NSMutableString(string: text)
            mutable.insert(string, at: location)
            text = mutable.copy() as! NSString
            highlighter.applyEdit(replacing: NSRange(location: location, length: 0), with: (string as NSString).length, in: text)
        }
        func matchesFreshParse() -> Bool {
            let fresh = SyntaxHighlighter(language: markdown)
            fresh.setText(text)
            let all = NSRange(location: 0, length: text.length)
            return highlighter.tokens(in: all) == fresh.tokens(in: all)
        }

        insert("x", at: 2)
        let beforeSetText = highlighter.beginPendingParse()!
        text = "Plain **bold** here\n" as NSString
        highlighter.setText(text)
        #expect(highlighter.finishPendingParse(beforeSetText.run()) == nil)
        #expect(matchesFreshParse())

        insert("_a_ ", at: 0)
        let older = highlighter.beginPendingParse()!
        insert("# ", at: 0)
        let newer = highlighter.beginPendingParse()!
        #expect(highlighter.finishPendingParse(older.run()) == nil)
        #expect(highlighter.finishPendingParse(newer.run()) != nil)
        #expect(!highlighter.hasPendingParse)
        #expect(matchesFreshParse())
    }

    @Test("edits and queries while a large Markdown file reparses on another thread")
    func concurrentBackgroundParse() async {
        let markdown = LanguageRegistry.language(id: "markdown")!
        let block = "## Section\n\nSome *emphasis*, `code` and a [link](https://example.com).\n\n- item one\n- item **two**\n\n```swift\nlet x = 1\n```\n\n"
        var text = ("# Document\n\n" + String(repeating: block, count: 300_000 / block.utf16.count)) as NSString
        let highlighter = SyntaxHighlighter(language: markdown)
        highlighter.deferredParseThreshold = .zero
        highlighter.setText(text)
        var generator = SeededGenerator(seed: 41)
        func edit() {
            let location = Int.random(in: 0...text.length, using: &generator)
            let insertion = ["*", "`", "\n", "# ", "x", "]("].randomElement(using: &generator)!
            let mutable = NSMutableString(string: text)
            mutable.insert(insertion, at: location)
            text = mutable.copy() as! NSString
            highlighter.applyEdit(replacing: NSRange(location: location, length: 0), with: (insertion as NSString).length, in: text)
            _ = highlighter.tokens(in: NSRange(location: max(0, location - 2_000), length: min(4_000, text.length - max(0, location - 2_000))))
        }
        edit()
        let job = highlighter.beginPendingParse()!
        let running = Task.detached { job.run() }
        for _ in 0..<40 { edit() }
        #expect(highlighter.finishPendingParse(await running.value) != nil)
        #expect(highlighter.hasPendingParse)
        highlighter.parsePending()
        let fresh = SyntaxHighlighter(language: markdown)
        fresh.setText(text)
        for start in stride(from: 0, to: text.length, by: text.length / 4) {
            let range = NSRange(location: start, length: min(5_000, text.length - start))
            #expect(highlighter.tokens(in: range) == fresh.tokens(in: range), "\(range)")
        }
        #expect(highlighter.foldRanges() == fresh.foldRanges())
    }

    @Test("an edit far from the viewport reports a small range")
    func localInvalidation() {
        let lines = (0..<500).map { "const value\($0) = compute(\($0), \"text\");" }
        let text = lines.joined(separator: "\n") as NSString
        let highlighter = SyntaxHighlighter(language: LanguageRegistry.language(id: "typescript")!)
        highlighter.setText(text)
        let location = text.range(of: "value250").location
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: NSRange(location: location, length: 0), with: "new")
        let changed = highlighter.applyEdit(replacing: NSRange(location: location, length: 0), with: 3, in: mutable)
        let total = changed.reduce(0) { $0 + $1.length }
        #expect(total < 200, "\(changed)")
        #expect(changed.allSatisfy { $0.location > 200 * 40 })
    }

    @Test("changing a fence's language re-highlights the block")
    func fenceLanguageChange() {
        let highlighter = SyntaxHighlighter(language: LanguageRegistry.language(id: "markdown")!)
        let text = "```ts\nlet x = None\n```\n" as NSString
        highlighter.setText(text)
        let before = highlighter.tokens(in: NSRange(location: 0, length: text.length))
        let noneRange = text.range(of: "None")
        #expect(before.first { $0.range == noneRange }?.kind == .type)  // capitalized identifier in TS
        let newText = "```py\nlet x = None\n```\n" as NSString
        let changed = highlighter.applyEdit(replacing: NSRange(location: 3, length: 2), with: 2, in: newText)
        #expect(changed.contains { $0.location <= noneRange.location && $0.upperBound >= noneRange.upperBound }, "\(changed)")
        let after = highlighter.tokens(in: NSRange(location: 0, length: newText.length))
        #expect(after.first { $0.range == noneRange }?.kind == .constant)  // Python's None
    }

    static func kindsPerUnit(_ highlighter: SyntaxHighlighter, _ text: NSString) -> [TokenKind?] {
        var kinds = [TokenKind?](repeating: nil, count: text.length)
        for token in highlighter.tokens(in: NSRange(location: 0, length: text.length)) {
            for index in token.range.location..<token.range.upperBound { kinds[index] = token.kind }
        }
        return kinds
    }
}
