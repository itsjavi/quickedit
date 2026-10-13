import Foundation
import Testing

@testable import QuickEditSyntax

@Suite("Fold ranges")
struct FoldTests {
    /// A fold described by the text it starts after (`opener`), the text right after its hidden range (`closer`,
    /// empty for line-based folds) and its lines.
    struct Fold: Equatable, CustomStringConvertible {
        let hidden: String
        let lines: ClosedRange<Int>
        var description: String { "\(lines): \(hidden.debugDescription)" }
    }

    private func folds(_ source: String, _ language: String) -> [Fold] {
        let text = source as NSString
        let highlighter = SyntaxHighlighter(language: LanguageRegistry.language(id: language)!)
        highlighter.setText(text)
        return highlighter.foldRanges().map {
            Fold(hidden: text.substring(with: $0.hidden), lines: $0.startLine...$0.endLine)
        }
    }

    @Test("JSON: objects and arrays between their brackets, nested; single-line ones don't fold")
    func json() {
        let result = folds(
            """
            {
              "name": "x",
              "list": [
                1,
                2
              ],
              "inline": { "a": { "b": 1 } },
              "obj": {
                "k": true
              }
            }
            """, "json")
        #expect(
            result == [
                Fold(
                    hidden:
                        "\n  \"name\": \"x\",\n  \"list\": [\n    1,\n    2\n  ],\n  \"inline\": { \"a\": { \"b\": 1 } },\n  \"obj\": {\n    \"k\": true\n  }\n",
                    lines: 0...10),
                Fold(hidden: "\n    1,\n    2\n  ", lines: 2...5),
                Fold(hidden: "\n    \"k\": true\n  ", lines: 7...9),
            ], "\(result)")
    }

    @Test("CSS: rule and at-rule blocks, nested")
    func css() {
        let result = folds(
            """
            .a {
              color: red;
            }
            @media (max-width: 600px) {
              .b {
                margin: 0;
              }
            }
            .c { color: blue; }
            """, "css")
        #expect(
            result == [
                Fold(hidden: "\n  color: red;\n", lines: 0...2),
                Fold(hidden: "\n  .b {\n    margin: 0;\n  }\n", lines: 3...7),
                Fold(hidden: "\n    margin: 0;\n  ", lines: 4...6),
            ], "\(result)")
    }

    @Test("YAML: mappings and sequence items by lines, flow collections by brackets")
    func yaml() {
        let result = folds(
            """
            name: ci
            on:
              push:
                branches: [main]
            jobs:
              build:
                steps:
                  - uses: actions/checkout@v4
                  - run: |
                      swift build
                      swift test
            flow: {
              a: 1
            }
            """, "yaml")
        #expect(
            result == [
                Fold(hidden: "\n  push:\n    branches: [main]", lines: 1...3),
                Fold(hidden: "\n    branches: [main]", lines: 2...3),
                Fold(
                    hidden:
                        "\n  build:\n    steps:\n      - uses: actions/checkout@v4\n      - run: |\n          swift build\n          swift test",
                    lines: 4...10),
                Fold(
                    hidden: "\n    steps:\n      - uses: actions/checkout@v4\n      - run: |\n          swift build\n          swift test",
                    lines: 5...10),
                Fold(
                    hidden: "\n      - uses: actions/checkout@v4\n      - run: |\n          swift build\n          swift test",
                    lines: 6...10),
                Fold(hidden: "\n          swift build\n          swift test", lines: 8...10),
                Fold(hidden: "\n  a: 1\n", lines: 11...13),
            ], "\(result)")
    }

    @Test("TOML: tables by lines, multi-line arrays and inline tables by brackets")
    func toml() {
        let result = folds(
            """
            title = "x"

            [package]
            name = "quickedit"
            deps = [
              "a",
              "b",
            ]

            [[bin]]
            name = "qe"
            path = "src/main.rs"
            """, "toml")
        #expect(
            result == [
                Fold(hidden: "\nname = \"quickedit\"\ndeps = [\n  \"a\",\n  \"b\",\n]", lines: 2...7),
                Fold(hidden: "\n  \"a\",\n  \"b\",\n", lines: 4...7),
                Fold(hidden: "\nname = \"qe\"\npath = \"src/main.rs\"", lines: 9...11),
            ], "\(result)")
    }

    @Test("folds follow edits and are recomputed after each one")
    func edits() {
        let highlighter = SyntaxHighlighter(language: LanguageRegistry.language(id: "json")!)
        let text = NSMutableString(string: "{\n  \"a\": [\n    1\n  ]\n}\n")
        highlighter.setText(text)
        #expect(highlighter.foldRanges().map(\.startLine) == [0, 1])
        // Insert a line above: everything moves down one line.
        text.insert("\n", at: 1)
        highlighter.applyEdit(replacing: NSRange(location: 1, length: 0), with: 1, in: text)
        #expect(highlighter.foldRanges().map(\.startLine) == [0, 2])
        #expect(highlighter.foldRanges().map(\.endLine) == [5, 4])
        // Collapse the array onto one line: its fold disappears.
        let array = text.range(of: "[\n    1\n  ]")
        text.replaceCharacters(in: array, with: "[1]")
        highlighter.applyEdit(replacing: array, with: 3, in: text)
        #expect(highlighter.foldRanges().count == 1)
        let fresh = SyntaxHighlighter(language: LanguageRegistry.language(id: "json")!)
        fresh.setText(text.copy() as! NSString)
        #expect(highlighter.foldRanges() == fresh.foldRanges())
    }

    @Test("other languages")
    func others() {
        let ts = folds(
            """
            export function Card(props: { title: string }) {
              return (
                <article>
                  <h2>{props.title}</h2>
                </article>
              );
            }
            interface Point {
              x: number;
            }
            """, "tsx")
        #expect(ts.map(\.lines) == [0...6, 1...5, 2...4, 7...9], "\(ts)")
        #expect(ts[2].hidden == "\n      <h2>{props.title}</h2>\n    ")

        let python = folds("def f(a):\n    if a:\n        return 1\n    return 2\n\nx = 1\n", "python")
        #expect(python.map(\.lines) == [0...3, 1...2], "\(python)")
        #expect(python[0].hidden == "\n    if a:\n        return 1\n    return 2")

        let markdown = folds("# A\n\ntext\n\n## B\n\nmore\n\n```js\nlet x;\n```\n", "markdown")
        #expect(markdown.map(\.lines) == [0...10, 4...10, 8...10], "\(markdown)")
        #expect(markdown[2].hidden == "\nlet x;\n")

        let html = folds("<ul>\n  <li>a</li>\n</ul>\n<p>x</p>\n", "html")
        #expect(html == [Fold(hidden: "\n  <li>a</li>\n", lines: 0...2)], "\(html)")

        let stsx = folds("export function A() {\n  return 1;\n}\n\n<style>\n  .a {\n    color: $c;\n  }\n</style>\n", "stsx")
        #expect(stsx.map(\.lines) == [0...2, 4...8, 5...7], "\(stsx)")

        for language in ["go", "rust", "swift", "xml", "javascript", "typescript", "sjsx"] {
            let samples = [
                "go": "func f() {\n\treturn\n}\n", "rust": "fn f() {\n    1\n}\n", "swift": "func f() {\n    g()\n}\n",
                "xml": "<a>\n  <b/>\n</a>\n", "javascript": "function f() {\n  g();\n}\n",
                "typescript": "function f(): void {\n  g();\n}\n", "sjsx": "function F() {\n  return <p>x</p>;\n}\n",
            ]
            #expect(folds(samples[language]!, language).map(\.lines) == [0...2], "\(language)")
        }
    }

    @Test("languages without folds")
    func none() {
        #expect(folds("a\n  b\n    c\n", "plaintext").isEmpty)
        #expect(folds("a,b\nc,d\n", "csv").isEmpty)
        #expect(folds("echo a\nif x; then\n  y\nfi\n", "shell").isEmpty)
        #expect(folds("", "json").isEmpty)
    }

    @Test("10k-line files fold fast")
    func performance() {
        let clock = ContinuousClock()
        let typescript = PerformanceTests.largeTypeScript as NSString
        let tsHighlighter = SyntaxHighlighter(language: LanguageRegistry.language(id: "typescript")!)
        tsHighlighter.setText(typescript)
        var tsFolds: [FoldRegion] = []
        let tsTime = clock.measure { tsFolds = tsHighlighter.foldRanges() }

        let entries = (0..<2_500).map { "  {\n    \"id\": \($0),\n    \"tags\": [\"a\", \"b\"]\n  }" }
        let json = ("[\n" + entries.joined(separator: ",\n") + "\n]\n") as NSString
        let jsonHighlighter = SyntaxHighlighter(language: LanguageRegistry.language(id: "json")!)
        jsonHighlighter.setText(json)
        var jsonFolds: [FoldRegion] = []
        let jsonTime = clock.measure { jsonFolds = jsonHighlighter.foldRanges() }

        print("PERF folds typescript=\(tsFolds.count) in \(tsTime), json=\(jsonFolds.count) in \(jsonTime)")
        #expect(tsFolds.count > 1_000)
        #expect(jsonFolds.count == 2_501)
        #expect(tsTime < Self.budget && jsonTime < Self.budget)
        // Cached until the next edit.
        #expect(clock.measure { _ = tsHighlighter.foldRanges() } < .milliseconds(1))
    }

    #if DEBUG
        static let budget = Duration.milliseconds(150)
    #else
        static let budget = Duration.milliseconds(10)
    #endif
}
