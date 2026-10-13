import Foundation
import Testing

@testable import QuickEditSyntax

@Suite("Injections")
struct InjectionTests {
    @Test("Markdown fenced code is highlighted by its info string's language")
    func markdownFences() {
        let h = Highlighted(
            """
            Intro with `code`.

            ```ts
            const x: number = 1;
            ```

            ```python
            def f(): return None
            ```

            ```bash
            echo "hi" # note
            ```

            ```json
            {"k": true}
            ```

            ```unknown
            const not_highlighted = 1
            ```

            > ```js
            > let quoted = 2;
            > ```

            """, language: "markdown")
        #expect(h.kind(of: "const") == .keyword, "\(h.dump)")
        #expect(h.kind(of: "number") == .type)
        #expect(h.kind(of: "def") == .keyword)
        #expect(h.kind(of: "None") == .constant)
        #expect(h.kind(of: "echo") == .function)
        #expect(h.kind(of: "# note") == .comment)
        #expect(h.kind(of: "\"k\"") == .property)
        #expect(h.kind(of: "true") == .constant)
        // Unknown languages leave the content plain.
        #expect(h.kinds(within: "const not_highlighted = 1").isEmpty)
        // Fences inside block quotes exclude the "> " markers from the injected code.
        #expect(h.kind(of: "let") == .keyword)
        #expect(h.kind(of: "2", after: "quoted = ") == .number)
    }

    @Test("Markdown inline syntax, front matter and HTML blocks")
    func markdownInline() {
        let h = Highlighted(
            """
            ---
            title: Hello
            draft: true
            ---

            # A *very* `nice` title

            Text with **strong**, _emphasis_, [a link](https://example.com) and <https://auto.link>.

            | Column | `Code` |
            | ------ | ------ |
            | *em*   | cell   |

            > Quote with `code` inside
            > and a second line

            <div class="box">
            html block
            </div>

            """, language: "markdown")
        #expect(h.kind(of: "title") == .property, "\(h.dump)")
        #expect(h.kind(of: "true") == .constant)
        #expect(h.kind(of: "# A ") == .heading)
        #expect(h.kind(of: "*very*") == .emphasis)
        #expect(h.kind(of: "`nice`") == .codeSpan)
        #expect(h.kind(of: "**strong**") == .strong)
        #expect(h.kind(of: "_emphasis_") == .emphasis)
        #expect(h.kind(of: "a link") == .link)
        #expect(h.kind(of: "https://example.com") == .link)
        #expect(h.kind(of: "https://auto.link") == .link)
        #expect(h.kind(of: "`Code`") == .codeSpan)
        #expect(h.kind(of: "*em*") == .emphasis)
        #expect(h.kind(of: "`code`", after: "Quote with ") == .codeSpan)
        #expect(h.kind(of: "and a second line") == .quote)
        #expect(h.kind(of: "div") == .tag)
        #expect(h.kind(of: "class") == .attribute)
    }

    @Test("HTML script and style elements")
    func htmlScriptStyle() {
        let h = Highlighted(
            """
            <html>
            <head>
            <style>
              .card { padding: 4px; }
            </style>
            <script type="module">
              import { x } from "./x.js";
              function go() { return x * 2; }
            </script>
            </head>
            <body onload="go()"><p>Hi</p></body>
            </html>
            """, language: "html")
        #expect(h.kind(of: "padding") == .property, "\(h.dump)")
        #expect(h.kind(of: "card") == .property)
        #expect(h.kind(of: "4") == .number)
        #expect(h.kind(of: "import") == .keyword)
        #expect(h.kind(of: "function") == .keyword)
        #expect(h.kind(of: "go", after: "function ") == .function)
        #expect(h.kind(of: "\"./x.js\"") == .string)
        #expect(h.kind(of: "type") == .attribute)
        #expect(h.kind(of: "body", after: "</head>\n<") == .tag)
    }

    @Test("nested injections: Markdown → HTML → JavaScript")
    func nested() {
        let h = Highlighted(
            """
            ```html
            <script>let deep = true;</script>
            ```

            """, language: "markdown")
        #expect(h.kind(of: "script") == .tag, "\(h.dump)")
        #expect(h.kind(of: "let") == .keyword)
        #expect(h.kind(of: "true") == .constant)
    }

    @Test("Makefile recipes and Dockerfile RUN lines are shell")
    func shellInjections() {
        let make = Highlighted("all:\n\techo \"building\" && ls -la\n", language: "makefile")
        #expect(make.kind(of: "\"building\"") == .string, "\(make.dump)")
        let docker = Highlighted("FROM alpine\nRUN apk add --no-cache git && echo 'ok'\n", language: "dockerfile")
        #expect(docker.kind(of: "apk") == .function, "\(docker.dump)")
        #expect(docker.kind(of: "'ok'") == .string)
    }

    @Test("tagged template literals are highlighted by their tag")
    func taggedTemplates() {
        let h = Highlighted(
            """
            const style = css`color: red; margin: ${size}px;`;
            const page = html`<p class="x">${name}</p>`;
            """, language: "javascript")
        #expect(h.kind(of: "color") == .property, "\(h.dump)")
        #expect(h.kind(of: "margin") == .property)
        #expect(h.kind(of: "p", after: "html`<") == .tag)
        #expect(h.kind(of: "class") == .attribute)
        #expect(h.kind(of: "size") == .variable)
    }

    @Test("ranges for injected layers exclude named children and respect parent ranges")
    func intersectRanges() throws {
        // `> ` markers are named children (block_continuation) of the fenced code content.
        let h = Highlighted("> ```js\n> a = 1\n> ```\n", language: "markdown")
        #expect(h.kind(of: "1") == .number, "\(h.dump)")
        #expect(h.kind(of: "a") == .variable)
    }
}
