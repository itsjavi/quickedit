import Foundation
import Testing

@testable import QuickEditSyntax

struct Expectation: Sendable {
    let needle: String
    let anchor: String?
    let kind: TokenKind

    init(_ needle: String, after anchor: String? = nil, _ kind: TokenKind) {
        self.needle = needle
        self.anchor = anchor
        self.kind = kind
    }
}

struct Fixture: Sendable, CustomTestStringConvertible {
    let language: String
    let source: String
    let expectations: [Expectation]

    var testDescription: String { language }
}

@Suite("Highlighting fixtures")
struct HighlightTests {
    static let fixtures: [Fixture] = [
        Fixture(
            language: "javascript",
            source: """
                // comment
                import { readFile } from "fs";
                const answer = 42;
                function greet(name) {
                  return `Hello ${name}`;
                }
                class Foo extends Bar {}
                console.log(greet("x"), this, null, /ab+c/g);
                const el = <div className="x">{answer}</div>;
                function Component() {}
                """,
            expectations: [
                .init("// comment", .comment), .init("import", .keyword), .init("\"fs\"", .string),
                .init("const", .keyword), .init("42", .number), .init("greet", .function),
                .init("name", after: "greet(", .parameter), .init("return", .keyword), .init("`Hello ", .string),
                .init("${", .stringSpecial), .init("Foo", .type), .init("console", .variableBuiltin),
                .init("log", .function), .init("this", .variableBuiltin), .init("null", .constant),
                .init("/ab+c/g", .stringSpecial), .init("div", .tag), .init("className", .attribute),
                .init("=", after: "answer ", .operator), .init("Component", .function),
            ]),
        Fixture(
            language: "typescript",
            source: """
                // comment
                interface Point { x: number; y?: string }
                const MAX_SIZE: number = 10;
                export function area(p: Point): number {
                  return p.x * 2;
                }
                type Alias = Point | null;
                enum Color { Red, Green }
                """,
            expectations: [
                .init("// comment", .comment), .init("interface", .keyword), .init("Point", .type),
                .init("number", .type), .init("const", .keyword), .init("MAX_SIZE", .constant), .init("10", .number),
                .init("export", .keyword), .init("area", .function), .init("p", after: "area(", .parameter),
                .init("x", after: "p.", .property), .init("type", after: "}\n", .keyword), .init("enum", .keyword),
                .init("null", .constant),
            ]),
        Fixture(
            language: "tsx",
            source: """
                const App = (props: Props) => <Button onClick={go}>Hi <b>there</b></Button>;
                """,
            expectations: [
                .init("const", .keyword), .init("Button", .type), .init("onClick", .attribute),
                .init("b", after: "Hi <", .tag), .init("props", .parameter), .init("Props", .type),
            ]),
        Fixture(
            language: "css",
            source: """
                /* comment */
                .btn > a:hover { color: #fff; margin: 0 auto !important; --gap: 4px; }
                @media (max-width: 600px) { body { width: calc(100% - 2px); } }
                """,
            expectations: [
                .init("/* comment */", .comment), .init("btn", .property), .init("a", after: "> ", .tag),
                .init("hover", .attribute), .init("color", .property), .init("#fff", .stringSpecial), .init("--gap", .variable),
                .init("!important", .keyword), .init("@media", .keyword), .init("600", .number),
                .init("px", after: "600", .type), .init("calc", .function), .init("body", .tag),
            ]),
        Fixture(
            language: "html",
            source: """
                <!DOCTYPE html>
                <html lang="en">
                <!-- comment -->
                <script>const x = 1;</script>
                <style>body { color: red; }</style>
                <p class="a">Hi &amp; bye</p>
                </html>
                """,
            expectations: [
                .init("DOCTYPE html", .constant), .init("html", after: "html>\n<", .tag), .init("lang", .attribute),
                .init("\"en\"", .string), .init("<!-- comment -->", .comment), .init("const", .keyword),
                .init("1", after: "x = ", .number), .init("body", .tag), .init("color", .property),
                .init("&amp;", .stringSpecial), .init("<", after: "</p>\n", .punctuation),
            ]),
        Fixture(
            language: "markdown",
            source: """
                # Heading *one*

                Some `code` and **bold** and _em_ and [link](https://x.y).

                > quote

                - item
                1. first

                ```ts
                const x: number = 1;
                ```

                ```
                plain code
                ```

                Setext
                ======

                """,
            expectations: [
                .init("# Heading", .heading), .init("one", .emphasis), .init("`code`", .codeSpan),
                .init("bold", .strong), .init("em", .emphasis), .init("link", .link), .init("https://x.y", .link),
                .init("> quote", .quote), .init("-", after: "quote\n\n", .listMarker), .init("1.", .listMarker),
                .init("ts", after: "```", .label), .init("const", .keyword), .init("number", .type),
                .init("plain code", .codeSpan), .init("Setext", .heading),
            ]),
        Fixture(
            language: "json",
            source: #"{"key": "value", "n": 1.5, "t": true, "z": null, "e": "a\nb"}"#,
            expectations: [
                .init("\"key\"", .property), .init("\"value\"", .string), .init("1.5", .number),
                .init("true", .constant), .init("null", .constant), .init(#"\n"#, .stringSpecial),
            ]),
        Fixture(
            language: "jsonc",
            source: """
                // comment
                {"a": 1 /* block */, "b": [true]}
                """,
            expectations: [
                .init("// comment", .comment), .init("/* block */", .comment), .init("\"a\"", .property),
                .init("true", .constant),
            ]),
        Fixture(
            language: "jsonl",
            source: """
                {"a": 1}
                {"b": "two"}
                """,
            expectations: [.init("\"a\"", .property), .init("\"b\"", .property), .init("\"two\"", .string)]),
        Fixture(
            language: "yaml",
            source: """
                # comment
                key: value
                list:
                  - 1
                  - true
                anchor: &anc x
                quoted: "str"
                """,
            expectations: [
                .init("# comment", .comment), .init("key", .property), .init("value", .string), .init("1", .number),
                .init("true", .constant), .init("\"str\"", .string), .init("anc", after: "&", .label),
            ]),
        Fixture(
            language: "toml",
            source: """
                # comment
                [package]
                name = "quickedit"
                version = 1
                enabled = true
                date = 1979-05-27
                deps.serde = "1.0"
                """,
            expectations: [
                .init("# comment", .comment), .init("package", .type), .init("name", .property),
                .init("\"quickedit\"", .string), .init("1", after: "version = ", .number), .init("true", .constant),
                .init("1979-05-27", .stringSpecial), .init("serde", .property), .init("=", .operator),
            ]),
        Fixture(
            language: "go",
            source: """
                // Package main does things.
                package main

                import "fmt"

                func main() {
                \tx := 42
                \tfmt.Println("hi", x, nil, true)
                }

                type Point struct{ X int }
                """,
            expectations: [
                .init("// Package main does things.", .comment), .init("package", .keyword), .init("\"fmt\"", .string),
                .init("func", .keyword), .init("main", after: "func ", .function), .init("42", .number),
                .init("Println", .function), .init("nil", .constant), .init("true", .constant),
                .init("Point", .type), .init("int", after: "X ", .type), .init("X", .property), .init(":=", .operator),
            ]),
        Fixture(
            language: "gomod",
            source: """
                module example.com/m

                go 1.22

                require (
                \tgithub.com/x/y v1.2.3 // indirect
                )
                """,
            expectations: [
                .init("module", .keyword), .init("example.com/m", .namespace), .init("go", after: "m\n\n", .keyword),
                .init("1.22", .string), .init("require", .keyword), .init("v1.2.3", .string),
                .init("// indirect", .comment),
            ]),
        Fixture(
            language: "rust",
            source: """
                // comment
                use std::fmt;
                const MAX: u32 = 10;
                fn main() {
                    let s = String::from("hi");
                    println!("{}", s);
                }
                struct Point { x: i32 }
                """,
            expectations: [
                .init("// comment", .comment), .init("use", .keyword), .init("const", .keyword), .init("MAX", .constant),
                .init("u32", .type), .init("10", .number), .init("fn", .keyword), .init("main", .function),
                .init("let", .keyword), .init("String", .type), .init("\"hi\"", .string), .init("println", .function),
                .init("Point", .type), .init("x", after: "Point { ", .property),
            ]),
        Fixture(
            language: "python",
            source: """
                # comment
                import os
                def greet(name: str) -> str:
                    \"\"\"Doc.\"\"\"
                    return f"hi {name}"
                class Foo(Base):
                    pass
                print(len(os.environ), None, True)
                os.path.join("a", "b")
                """,
            expectations: [
                .init("# comment", .comment), .init("import", .keyword), .init("def", .keyword),
                .init("greet", .function), .init("\"\"\"Doc.\"\"\"", .string), .init("return", .keyword),
                .init("f\"hi ", .string), .init("Foo", .type), .init("pass", .keyword), .init("print", .function),
                .init("None", .constant), .init("True", .constant), .init("environ", .property),
                .init("join", .function),
            ]),
        Fixture(
            language: "swift",
            source: """
                // comment
                import Foundation
                struct Point { let x: Int }
                func area(of p: Point) -> Double {
                    return Double(p.x) * 2.5
                }
                let s = "hi \\(1)"
                """,
            expectations: [
                .init("// comment", .comment), .init("import", .keyword), .init("struct", .keyword),
                .init("Point", .type), .init("Int", .type), .init("func", .keyword), .init("area", .function),
                .init("return", .keyword), .init("2.5", .number), .init("\"hi ", .string),
            ]),
        Fixture(
            language: "gdscript",
            source: """
                extends Node2D
                class_name Player
                # comment
                const SPEED := 200.0
                @export var health: int = 10
                signal died
                func _ready() -> void:
                \tvar v = Vector2(1, 2)
                \tprint("hi", self, null)
                \t$Sprite.visible = true
                """,
            expectations: [
                .init("extends", .keyword), .init("Node2D", .type), .init("Player", .type), .init("# comment", .comment),
                .init("SPEED", .constant), .init("200.0", .number), .init("@export", .attribute), .init("var", .keyword),
                .init("int", .type), .init("func", .keyword), .init("_ready", .function), .init("\"hi\"", .string),
                .init("self", .variableBuiltin), .init("null", .constant), .init("$Sprite", .stringSpecial),
                .init("true", .constant), .init("print", .function), .init("died", .function),
            ]),
        Fixture(
            language: "godot-resource",
            source: """
                [gd_scene load_steps=2 format=3 uid="uid://abc"]

                [node name="Player" type="CharacterBody2D"]
                script = ExtResource("1")
                position = Vector2(10, 20.5)
                ; comment
                """,
            expectations: [
                .init("gd_scene", .keyword), .init("load_steps", .attribute), .init("2", .number),
                .init("\"uid://abc\"", .string), .init("script", .property), .init("ExtResource", .type),
                .init("20.5", .number), .init("; comment", .comment),
            ]),
        Fixture(
            language: "gdshader",
            source: """
                shader_type canvas_item;
                uniform vec4 tint : source_color = vec4(1.0);
                // comment
                void fragment() {
                \tCOLOR = texture(TEXTURE, UV) * tint;
                }
                """,
            expectations: [
                .init("shader_type", .keyword), .init("uniform", .keyword), .init("vec4", .type), .init("1.0", .number),
                .init("// comment", .comment), .init("fragment", .function), .init("UV", .constant),
                .init("texture", .function),
            ]),
        Fixture(
            language: "dockerfile",
            source: """
                # comment
                FROM node:20 AS build
                ENV NODE_ENV=production
                RUN npm ci && echo "done"
                CMD ["node", "server.js"]
                """,
            expectations: [
                .init("# comment", .comment), .init("FROM", .keyword), .init("AS", .keyword), .init("RUN", .keyword),
                .init("\"server.js\"", .string), .init("npm", .function), .init("echo", .function),
                .init("\"done\"", .string),
            ]),
        Fixture(
            language: "xml",
            source: """
                <?xml version="1.0" encoding="UTF-8"?>
                <!-- comment -->
                <plist version="1.0">
                  <dict><key>Name</key><string>&amp;</string></dict>
                </plist>
                """,
            expectations: [
                .init("xml", .keyword), .init("<!-- comment -->", .comment), .init("plist", .tag),
                .init("version", after: "<plist ", .attribute), .init("\"1.0\"", after: "<plist ", .string),
                .init("dict", .tag), .init("&amp;", .constant),
            ]),
        Fixture(
            language: "dtd",
            source: """
                <!ELEMENT note (to,from)>
                <!ATTLIST note id CDATA #REQUIRED>
                """,
            expectations: [.init("ELEMENT", .keyword), .init("note", .tag), .init("#REQUIRED", .attribute)]),
        Fixture(
            language: "ini",
            source: """
                ; comment
                [section]
                key = value
                """,
            expectations: [
                .init("; comment", .comment), .init("section", .type), .init("key", .property),
                .init("value", .string), .init("=", .operator),
            ]),
        Fixture(
            language: "shell",
            source: """
                #!/bin/bash
                # comment
                export NAME="world"
                if [ -n "$NAME" ]; then
                  echo "hello $NAME" | grep -i hello
                fi
                greet() { local x=1; return 0; }
                """,
            expectations: [
                .init("# comment", .comment), .init("export", .keyword), .init("NAME", .variable), .init("if", .keyword),
                .init("echo", .function), .init("\"hello ", .string), .init("$NAME", after: "hello ", .stringSpecial),
                .init("-i", .constant), .init("greet", .function), .init("local", .keyword), .init("fi", .keyword),
                .init("|", .operator),
            ]),
        Fixture(
            language: "dotenv",
            source: """
                # comment
                API_KEY=abc123
                QUOTED="hello world"
                export DEBUG=1
                """,
            expectations: [
                .init("# comment", .comment), .init("API_KEY", .variable), .init("abc123", .string),
                .init("\"hello world\"", .string), .init("export", .keyword),
            ]),
        Fixture(
            language: "makefile",
            source: """
                # comment
                CC := clang
                .PHONY: all
                all: main.o
                \t$(CC) -o app main.o
                ifeq ($(OS),Darwin)
                endif
                """,
            expectations: [
                .init("# comment", .comment), .init("ifeq", .keyword), .init("endif", .keyword),
                .init(":=", .operator),
            ]),
        Fixture(
            language: "sql",
            source: """
                -- comment
                SELECT id, name FROM users WHERE age > 21 AND active = TRUE;
                INSERT INTO t (a) VALUES ('x');
                """,
            expectations: [
                .init("-- comment", .comment), .init("SELECT", .keyword), .init("FROM", .keyword),
                .init("users", .type), .init("21", .number), .init("'x'", .string), .init("TRUE", .constant),
                .init("INSERT", .keyword),
            ]),
        Fixture(
            language: "ignore",
            source: """
                # comment
                node_modules/
                *.log
                !keep.log
                """,
            expectations: [.init("# comment", .comment), .init("*", .keyword), .init("!", .operator)]),
        Fixture(
            language: "gitattributes",
            source: """
                # comment
                *.png binary
                *.sh text eol=lf
                """,
            expectations: [.init("# comment", .comment), .init("binary", .variableBuiltin), .init("eol", .variableBuiltin)]),
        Fixture(
            language: "diff",
            source: """
                diff --git a/f.txt b/f.txt
                index 83db48f..bf269f4 100644
                --- a/f.txt
                +++ b/f.txt
                @@ -1,3 +1,3 @@
                 context
                -old line
                +new line
                """,
            expectations: [
                .init("-old line", .deleted), .init("+new line", .inserted), .init("@@ -1,3 +1,3 @@", .diffMeta),
                .init("diff --git a/f.txt b/f.txt", .diffMeta), .init("--- a/f.txt", .deleted),
                .init("+++ b/f.txt", .inserted),
            ]),
    ]

    @Test("fixtures highlight with the expected kinds", arguments: fixtures)
    func fixture(_ fixture: Fixture) {
        let highlighted = Highlighted(fixture.source, language: fixture.language)
        #expect(!highlighted.tokens.isEmpty)
        for expectation in fixture.expectations {
            let kind = highlighted.kind(of: expectation.needle, after: expectation.anchor)
            #expect(
                kind == expectation.kind,
                "\(fixture.language): \(expectation.needle.debugDescription) is \(String(describing: kind)), expected \(expectation.kind)\n\(highlighted.dump)"
            )
        }
    }

    @Test("every highlighted language has a fixture")
    func coverage() {
        let covered = Set((Self.fixtures + MoreLanguagesTests.fixtures).map(\.language))
        let highlighted = LanguageRegistry.all.filter { if case .grammar = $0.highlighting { true } else { false } }
        for language in highlighted {
            #expect(covered.contains(language.id), "no fixture for \(language.id)")
        }
    }

    @Test("tokens are sorted, non-overlapping and clipped to the requested range")
    func tokenInvariants() {
        for fixture in Self.fixtures {
            let language = LanguageRegistry.language(id: fixture.language)!
            let highlighter = SyntaxHighlighter(language: language)
            let text = fixture.source as NSString
            highlighter.setText(text)
            for start in stride(from: 0, to: text.length, by: 7) {
                let range = NSRange(location: start, length: min(23, text.length - start))
                let tokens = highlighter.tokens(in: range)
                var previousEnd = range.location
                for token in tokens {
                    #expect(token.range.location >= previousEnd, "\(fixture.language) overlap at \(token.range)")
                    #expect(token.range.length > 0)
                    #expect(token.range.upperBound <= range.upperBound)
                    previousEnd = token.range.upperBound
                }
            }
        }
    }

    @Test("plain text has no tokens")
    func plainText() {
        let highlighter = SyntaxHighlighter(language: LanguageRegistry.plainText)
        let text = "fn main() { let x = 1; } // not code" as NSString
        highlighter.setText(text)
        #expect(highlighter.tokens(in: NSRange(location: 0, length: text.length)).isEmpty)
        #expect(highlighter.applyEdit(replacing: NSRange(location: 0, length: 2), with: 0, in: "main()" as NSString).isEmpty)
    }

    @Test("empty and out-of-range requests")
    func edgeRanges() {
        let highlighter = SyntaxHighlighter(language: LanguageRegistry.language(id: "typescript")!)
        #expect(highlighter.tokens(in: NSRange(location: 0, length: 10)).isEmpty)
        highlighter.setText("")
        #expect(highlighter.tokens(in: NSRange(location: 0, length: 10)).isEmpty)
        let text = "const x = 1;" as NSString
        highlighter.setText(text)
        #expect(highlighter.tokens(in: NSRange(location: 5, length: 0)).isEmpty)
        #expect(highlighter.tokens(in: NSRange(location: 100, length: 10)).isEmpty)
        #expect(highlighter.tokens(in: NSRange(location: 0, length: 1000)).first?.kind == .keyword)
    }

    @Test("emoji and other surrogate pairs keep UTF-16 offsets")
    func utf16Offsets() {
        let highlighted = Highlighted("const s = \"😀😀\"; // 💥 done\nlet n = 1;", language: "typescript")
        #expect(highlighted.kind(of: "\"😀😀\"") == .string)
        #expect(highlighted.kind(of: "// 💥 done") == .comment)
        #expect(highlighted.kind(of: "let") == .keyword)
        #expect(highlighted.kind(of: "1") == .number)
    }
}

@MainActor
@Suite("Main-actor use")
struct MainActorTests {
    @MainActor
    final class Editor {
        let highlighter = SyntaxHighlighter(language: LanguageRegistry.detect(fileName: "main.swift", firstLine: nil))
    }

    @Test("a highlighter can live in main-actor state")
    func mainActor() {
        let editor = Editor()
        editor.highlighter.setText("let x = 1")
        #expect(editor.highlighter.tokens(in: NSRange(location: 0, length: 9)).first?.kind == .keyword)
    }
}
