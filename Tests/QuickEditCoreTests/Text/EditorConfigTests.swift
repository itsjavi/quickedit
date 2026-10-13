import Foundation
import QuickEditCore
import Testing

@Suite struct EditorConfigParseTests {
    @Test func parsesRootSectionsAndComments() {
        let text = """
        \u{FEFF}# top comment
        ROOT = True
        ; another comment

        [*]
        Indent_Style = Space
        indent_size=4
          # indented comment
        [*.{js,ts}]
        indent_size = 2
        not a property
        = no key
        [Makefile]
        indent_style = tab
        """
        let parsed = EditorConfig.parse(text)
        #expect(parsed.isRoot)
        #expect(parsed.sections.map(\.glob) == ["*", "*.{js,ts}", "Makefile"])
        #expect(parsed.sections[0].properties == ["indent_style": "Space", "indent_size": "4"])
        #expect(parsed.sections[1].properties == ["indent_size": "2"])
        #expect(parsed.sections[2].properties == ["indent_style": "tab"])
    }

    @Test func rootOnlyCountsInThePreamble() {
        #expect(!EditorConfig.parse("[*]\nroot = true\n").isRoot)
        #expect(!EditorConfig.parse("root = false\n").isRoot)
    }

    @Test func crlfAndCRLines() {
        let parsed = EditorConfig.parse("root = true\r\n[*]\r\nend_of_line = crlf\r[*.md]\rtrim_trailing_whitespace = false")
        #expect(parsed.isRoot)
        #expect(parsed.sections.count == 2)
        #expect(parsed.sections[0].properties["end_of_line"] == "crlf")
        #expect(parsed.sections[1].properties["trim_trailing_whitespace"] == "false")
    }
}

@Suite struct EditorConfigGlobTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let glob: String
        let path: String
        let matches: Bool
        var testDescription: String { "[\(glob)] \(matches ? "~" : "!~") \(path)" }
    }

    static let cases: [Case] = [
        // * and basename matching at any depth
        Case(glob: "*", path: "a.txt", matches: true),
        Case(glob: "*", path: "deep/dir/a.txt", matches: true),
        Case(glob: "*.py", path: "src/main.py", matches: true),
        Case(glob: "*.py", path: "main.pyc", matches: false),
        Case(glob: "a*e.c", path: "abcde.c", matches: true),
        Case(glob: "a*e.c", path: "ae.c", matches: true),
        Case(glob: "Makefile", path: "Makefile", matches: true),
        Case(glob: "Makefile", path: "sub/Makefile", matches: true),
        Case(glob: "Makefile", path: "Makefile.am", matches: false),
        Case(glob: "Makefile", path: "makefile", matches: false),
        // ?
        Case(glob: "?.c", path: "a.c", matches: true),
        Case(glob: "?.c", path: "ab.c", matches: false),
        Case(glob: "a?c", path: "a/c", matches: false),
        // brackets
        Case(glob: "[ab].a", path: "b.a", matches: true),
        Case(glob: "[ab].a", path: "c.a", matches: false),
        Case(glob: "[!ab].b", path: "c.b", matches: true),
        Case(glob: "[!ab].b", path: "a.b", matches: false),
        Case(glob: "[d-g].c", path: "f.c", matches: true),
        Case(glob: "[d-g].c", path: "h.c", matches: false),
        Case(glob: "[!d-g].d", path: "h.d", matches: true),
        Case(glob: "[-ab].f", path: "-.f", matches: true),
        Case(glob: "[\\]ab].g", path: "].g", matches: true),
        Case(glob: "[ab\\]].h", path: "].h", matches: true),
        Case(glob: "[!\\]ab].i", path: "c.i", matches: true),
        Case(glob: "[!\\]ab].i", path: "].i", matches: false),
        Case(glob: "ab[e/]cd.i", path: "ab[e/]cd.i", matches: true),
        Case(glob: "ab[e/]cd.i", path: "abecd.i", matches: false),
        Case(glob: "[unclosed", path: "[unclosed", matches: true),
        // braces
        Case(glob: "*.{js,ts}", path: "app.ts", matches: true),
        Case(glob: "*.{js,ts}", path: "lib/app.js", matches: true),
        Case(glob: "*.{js,ts}", path: "app.tsx", matches: false),
        Case(glob: "{word,{also},this}.g", path: "word.g", matches: true),
        Case(glob: "{word,{also},this}.g", path: "{also}.g", matches: true),
        Case(glob: "{word,{also},this}.g", path: "also.g", matches: false),
        Case(glob: "{single}.b", path: "{single}.b", matches: true),
        Case(glob: "{single}.b", path: "single.b", matches: false),
        Case(glob: "{}.c", path: "{}.c", matches: true),
        Case(glob: "a{b,c,}.d", path: "a.d", matches: true),
        Case(glob: "a{b,c,}.d", path: "ac.d", matches: true),
        Case(glob: "{.e", path: "{.e", matches: true),
        Case(glob: "}.f", path: "}.f", matches: true),
        Case(glob: "{{,b,c{d}.i", path: "{{,b,c{d}.i", matches: true),
        Case(glob: "{a\\,b,cd}", path: "a,b", matches: true),
        Case(glob: "{a\\,b,cd}", path: "cd", matches: true),
        Case(glob: "{e,\\},f}", path: "}", matches: true),
        Case(glob: "{some,a{*c,b}[ef]}.j", path: "abe.j", matches: true),
        Case(glob: "{some,a{*c,b}[ef]}.j", path: "a.cf.j", matches: true),
        Case(glob: "{some,a{*c,b}[ef]}.j", path: "some.j", matches: true),
        Case(glob: "{some,a{*c,b}[ef]}.j", path: "abg.j", matches: false),
        // numeric ranges
        Case(glob: "{1..3}", path: "2", matches: true),
        Case(glob: "{1..3}", path: "4", matches: false),
        Case(glob: "file{1..3}.txt", path: "file3.txt", matches: true),
        Case(glob: "file{1..3}.txt", path: "file0.txt", matches: false),
        Case(glob: "{3..120}", path: "120", matches: true),
        Case(glob: "{3..120}", path: "121", matches: false),
        Case(glob: "{3..120}", path: "060", matches: false),
        Case(glob: "{3..120}", path: "5a", matches: false),
        Case(glob: "{-5..5}", path: "-3", matches: true),
        Case(glob: "{aardvark..antelope}", path: "{aardvark..antelope}", matches: true),
        Case(glob: "{x,{1..3}}", path: "x", matches: true),
        // ** and slashes
        Case(glob: "a**z.c", path: "a/b/z.c", matches: true),
        Case(glob: "b/**z.c", path: "b/z.c", matches: true),
        Case(glob: "b/**z.c", path: "b/c/d/z.c", matches: true),
        Case(glob: "c**/z.c", path: "c/z.c", matches: true),
        Case(glob: "c**/z.c", path: "cd/e/z.c", matches: true),
        Case(glob: "d/**/z.c", path: "d/z.c", matches: true),
        Case(glob: "d/**/z.c", path: "d/x/y/z.c", matches: true),
        Case(glob: "d/**/z.c", path: "e/d/z.c", matches: false),
        Case(glob: "**/test/**", path: "test/a.swift", matches: true),
        Case(glob: "**/test/**", path: "src/test/unit/a.swift", matches: true),
        Case(glob: "**/test/**", path: "src/testing/a.swift", matches: false),
        Case(glob: "lib/**.js", path: "lib/a.js", matches: true),
        Case(glob: "lib/**.js", path: "lib/x/y/a.js", matches: true),
        Case(glob: "lib/**.js", path: "other/lib/a.js", matches: false),
        Case(glob: "src/*.c", path: "src/a.c", matches: true),
        Case(glob: "src/*.c", path: "src/sub/a.c", matches: false),
        Case(glob: "/top.txt", path: "top.txt", matches: true),
        Case(glob: "/top.txt", path: "sub/top.txt", matches: false),
        Case(glob: "**.md", path: "docs/deep/readme.md", matches: true),
        // escapes and regex metacharacters
        Case(glob: "\\*.txt", path: "*.txt", matches: true),
        Case(glob: "\\*.txt", path: "a.txt", matches: false),
        Case(glob: "a+b(c).txt", path: "a+b(c).txt", matches: true),
        Case(glob: "a.c", path: "abc", matches: false),
    ]

    @Test(arguments: cases)
    func glob(_ testCase: Case) {
        #expect(EditorConfig.matches(glob: testCase.glob, relativePath: testCase.path) == testCase.matches)
    }

    @Test func leadingSlashInPathIsAccepted() {
        #expect(EditorConfig.matches(glob: "*.md", relativePath: "/docs/a.md"))
    }
}

@Suite struct EditorConfigResolutionTests {
    /// Resolves against an in-memory file system of `.editorconfig` paths.
    private func properties(_ files: [String: String], for path: String) -> EditorConfigProperties {
        EditorConfig.properties(for: URL(fileURLWithPath: path)) { files[$0.path] }
    }

    @Test func nearestFileWins() {
        let files = [
            "/p/.editorconfig": "root = true\n[*]\nindent_style = space\nindent_size = 4\nend_of_line = lf\n",
            "/p/sub/.editorconfig": "[*]\nindent_size = 2\n",
        ]
        let result = properties(files, for: "/p/sub/a.js")
        #expect(result.indentStyle == .spaces)
        #expect(result.indentSize == 2)
        #expect(result.tabWidth == 2)
        #expect(result.endOfLine == .lf)
        #expect(properties(files, for: "/p/b.js").indentSize == 4)
    }

    @Test func rootStopsTheWalk() {
        let files = [
            "/.editorconfig": "[*]\nend_of_line = crlf\ninsert_final_newline = true\n",
            "/p/.editorconfig": "root = true\n[*.txt]\ntrim_trailing_whitespace = true\n",
        ]
        let result = properties(files, for: "/p/a.txt")
        #expect(result.endOfLine == nil)
        #expect(result.trimTrailingWhitespace == true)
    }

    @Test func walksToTheFilesystemRootWithoutARootFile() {
        let files = [
            "/.editorconfig": "[*]\nend_of_line = crlf\n",
            "/a/.editorconfig": "[*.c]\ninsert_final_newline = true\n",
        ]
        let result = properties(files, for: "/a/b/c/d.c")
        #expect(result.endOfLine == .crlf)
        #expect(result.insertFinalNewline == true)
    }

    @Test func laterSectionsWinWithinAFile() {
        let files = ["/p/.editorconfig": "[*]\nindent_size = 4\n[*.md]\nindent_size = 3\n[*]\ncharset = utf-8\n"]
        let result = properties(files, for: "/p/README.md")
        #expect(result.indentSize == 3)
        #expect(result.charset == .utf8)
    }

    @Test func globsWithSlashesAreRelativeToTheirFile() {
        let files = [
            "/p/.editorconfig": "root = true\n[lib/**.js]\nindent_size = 2\n[Makefile]\nindent_style = tab\n",
        ]
        #expect(properties(files, for: "/p/lib/x/a.js").indentSize == 2)
        #expect(properties(files, for: "/p/src/lib/a.js").indentSize == nil)
        #expect(properties(files, for: "/p/deep/dir/Makefile").indentStyle == .tabs)
    }

    @Test func unsetClearsOuterValues() {
        let files = [
            "/p/.editorconfig": "root = true\n[*]\nindent_style = space\ntrim_trailing_whitespace = true\n",
            "/p/sub/.editorconfig": "[*.md]\ntrim_trailing_whitespace = unset\n",
        ]
        let result = properties(files, for: "/p/sub/a.md")
        #expect(result.trimTrailingWhitespace == nil)
        #expect(result.indentStyle == .spaces)
    }

    @Test func indentSizeTab() {
        let withTabWidth = ["/p/.editorconfig": "root = true\n[*]\nindent_style = tab\nindent_size = tab\ntab_width = 8\n"]
        let result = properties(withTabWidth, for: "/p/a.go")
        #expect(result.indentStyle == .tabs)
        #expect(result.indentSize == 8)
        #expect(result.tabWidth == 8)

        let impliedByStyle = ["/p/.editorconfig": "root = true\n[*]\nindent_style = tab\ntab_width = 3\n"]
        #expect(properties(impliedByStyle, for: "/p/a.go").indentSize == 3)

        let unknownWidth = ["/p/.editorconfig": "root = true\n[*]\nindent_size = tab\n"]
        let unknown = properties(unknownWidth, for: "/p/a.go")
        #expect(unknown.indentSize == nil)
        #expect(unknown.tabWidth == nil)
    }

    @Test func explicitTabWidthIsKept() {
        let files = ["/p/.editorconfig": "root = true\n[*]\nindent_size = 2\ntab_width = 8\n"]
        let result = properties(files, for: "/p/a.c")
        #expect(result.indentSize == 2)
        #expect(result.tabWidth == 8)
    }

    @Test func valuesAreCaseInsensitiveAndValidated() {
        let files = [
            "/p/.editorconfig": """
            root = true
            [*]
            INDENT_STYLE = Tab
            End_Of_Line = CRLF
            charset = UTF-8-BOM
            trim_trailing_whitespace = TRUE
            insert_final_newline = False
            indent_size = -2
            tab_width = wide
            """,
        ]
        let result = properties(files, for: "/p/a.txt")
        #expect(result.indentStyle == .tabs)
        #expect(result.endOfLine == .crlf)
        #expect(result.charset == .utf8WithBOM)
        #expect(result.trimTrailingWhitespace == true)
        #expect(result.insertFinalNewline == false)
        #expect(result.indentSize == nil)
        #expect(result.tabWidth == nil)
    }

    @Test(arguments: [
        ("latin1", TextEncoding.isoLatin1), ("utf-8", .utf8), ("utf-8-bom", .utf8WithBOM),
        ("utf-16be", .utf16BigEndian), ("utf-16le", .utf16LittleEndian),
    ])
    func charsets(value: String, expected: TextEncoding) {
        let files = ["/p/.editorconfig": "root = true\n[*]\ncharset = \(value)\n"]
        #expect(properties(files, for: "/p/a.txt").charset == expected)
    }

    @Test func inlineCommentsAfterValuesAreTolerated() {
        let files = ["/p/.editorconfig": "root = true\n[*]\nindent_style = space # comment\nindent_size = 4 ; why\n"]
        let result = properties(files, for: "/p/a.txt")
        #expect(result.indentStyle == .spaces)
        #expect(result.indentSize == 4)
    }

    @Test func noConfigIsEmpty() {
        #expect(properties([:], for: "/p/a.txt").isEmpty)
        #expect(!EditorConfigProperties(endOfLine: .lf).isEmpty)
        let unrelated = ["/p/.editorconfig": "root = true\n[*.md]\nindent_size = 2\n"]
        #expect(properties(unrelated, for: "/p/a.txt").isEmpty)
    }

    @Test func readsRealFilesWithTheDefaultReader() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("editorconfig-\(UUID().uuidString)")
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "root = true\n[*]\nindent_style = tab\n".write(to: root.appendingPathComponent(".editorconfig"), atomically: true, encoding: .utf8)
        try "[*.swift]\nindent_style = space\nindent_size = 4\n".write(to: sub.appendingPathComponent(".editorconfig"), atomically: true, encoding: .utf8)
        let swift = EditorConfig.properties(for: sub.appendingPathComponent("a.swift"))
        #expect(swift.indentStyle == .spaces)
        #expect(swift.indentSize == 4)
        #expect(EditorConfig.properties(for: sub.appendingPathComponent("Makefile")).indentStyle == .tabs)
    }
}
