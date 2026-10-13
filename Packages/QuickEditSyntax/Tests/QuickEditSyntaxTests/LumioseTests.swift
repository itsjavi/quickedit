import Foundation
import Testing

@testable import QuickEditSyntax

/// Lumiose components (`.stsx`/`.sjsx`): TSX/JSX with raw-CSS `<style>` blocks. Fixtures are trimmed from the
/// Lumiose examples (ssg-travel-journal) and docs.
@Suite("Lumiose components")
struct LumioseTests {
    static let postCard = """
        import { href } from "lumiose";
        import * as theme from "../theme.ts";

        /** A grid of post cards; with `feature`, the first card spans the full width. */
        export function PostGrid(props: { posts: readonly Post[]; feature?: boolean }) {
          return (
            <div class="grid">
              {props.posts.map((post, index) => (
                <PostCard post={post} featured={props.feature === true && index === 0} />
              ))}
            </div>
          );
        }

        <style>
          .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(min(100%, 19rem), 1fr));
            gap: $theme.space.xl $theme.space.lg;
          }
          .card:hover {
            translate: 0 -3px;
            box-shadow: $theme.shadow.lift;
          }
          h2 a::after {
            content: "";
            position: absolute;
          }
          @media (width < $theme.layout.narrow) {
            .featured {
              grid-template-columns: none;
            }
          }
        </style>

        """

    static let layout = """
        // Root layout: header, page, footer, and the site's global styles.
        import type { LayoutProps } from "lumiose";
        import * as theme from "../theme.ts";

        export default function RootLayout(props: LayoutProps<"/">) {
          return (
            <>
              <a class="skip-link" href="#content">
                Skip to content
              </a>
              <main id="content">{props.children}</main>
            </>
          );
        }

        <style global>
          /* Cross-document View Transitions: same-origin navigations cross-fade. */
          :root[data-theme="dark"] {
            color-scheme: dark;
          }
          body {
            background: $theme.color.paper;
            font-family: $theme.font.body;
          }
        </style>

        export const after = { value: 1 };

        """

    static let nested = """
        import { accent, radius } from "../tokens.ts";

        export function Button(props: { label: string; onClick?: () => void }) {
          const gap = 12;
          return (
            <button class="button" onClick={props.onClick}>
              {props.label}
              <style>
                .button { border-radius: $radius.lg; background: $accent; gap: calc($gap * 1px); }
                .button::after { content: "→ ✨ $notRef"; } /* $alsoNotRef */
              </style>
            </button>
          );
        }

        const label = "<style> in a string is not a block";
        // <style> in a comment is not a block either
        const template = `<style>${label}</style>`;
        export const count = 2;

        """

    static let counter = """
        import { signal } from "lumiose";

        const accent = "#5546ff";

        export function Counter() {
          const count = signal(0);
          return <button class="counter" onClick={() => count.update((n) => n + 1)}>{count()}</button>;
        }

        <style>
          .counter { color: $accent; padding: 0.5rem 1rem; }
        </style>

        """

    @Test("registry and detection")
    func registry() {
        #expect(LanguageRegistry.detect(fileName: "PostCard.stsx", firstLine: nil).id == "stsx")
        #expect(LanguageRegistry.detect(fileName: "Counter.sjsx", firstLine: nil).id == "sjsx")
        let stsx = LanguageRegistry.language(id: "stsx")!
        #expect(stsx.displayName == "Lumiose TSX")
        #expect(stsx.lineComment == "//")
        #expect(stsx.blockComment == BlockComment(open: "/*", close: "*/"))
        #expect(stsx.hasHighlighting)
        #expect(LanguageRegistry.language(id: "sjsx")!.displayName == "Lumiose JSX")
        #expect(LanguageRegistry.language(forFenceInfo: "stsx")?.id == "stsx")
        #expect(GrammarStore.grammarName(forInjection: "stsx") == "tsx")
        #expect(GrammarStore.grammarName(forInjection: "sjsx") == "tsx")
    }

    @Test("a file-level <style> block is CSS with $references, and the components stay TSX")
    func fileLevelBlock() {
        let h = Highlighted(Self.postCard, language: "stsx")
        #expect(h.kind(of: "import") == .keyword, "\(h.dump)")
        #expect(h.kind(of: "PostGrid") == .function)
        #expect(h.kind(of: "boolean") == .type)
        #expect(h.kind(of: "div") == .tag)
        #expect(h.kind(of: "class") == .attribute)
        #expect(h.kind(of: "style", after: "\n<") == .tag)
        #expect(h.kind(of: "grid", after: "<style>\n  .") == .property)
        #expect(h.kind(of: "display") == .property)
        #expect(h.kind(of: "repeat") == .function)
        #expect(h.kind(of: "100") == .number)
        #expect(h.kind(of: "$theme.space.xl") == .constant)
        #expect(h.kind(of: "$theme.space.lg") == .constant)
        #expect(h.kind(of: "hover") == .attribute)
        #expect(h.kind(of: "$theme.shadow.lift") == .constant)
        #expect(h.kind(of: "\"\"", after: "content: ") == .string)
        #expect(h.kind(of: "@media") == .keyword)
        #expect(h.kind(of: "$theme.layout.narrow") == .constant)
        #expect(h.kind(of: "grid-template-columns", after: ".featured") == .property)
        #expect(h.kind(of: "style", after: "</") == .tag)
    }

    @Test("<style global> blocks, CSS comments and code after the block")
    func globalBlock() {
        let h = Highlighted(Self.layout, language: "stsx")
        #expect(h.kind(of: "// Root layout: header, page, footer, and the site's global styles.") == .comment, "\(h.dump)")
        #expect(h.kind(of: "RootLayout") == .function)
        #expect(h.kind(of: "global", after: "<style ") == .attribute)
        #expect(h.kind(of: "/* Cross-document View Transitions: same-origin navigations cross-fade. */") == .comment)
        #expect(h.kind(of: "data-theme") == .attribute)
        #expect(h.kind(of: "\"dark\"") == .string)
        #expect(h.kind(of: "color-scheme") == .property)
        #expect(h.kind(of: "body") == .tag)
        #expect(h.kind(of: "$theme.color.paper") == .constant)
        #expect(h.kind(of: "$theme.font.body") == .constant)
        // After the block: TSX again.
        #expect(h.kind(of: "export", after: "</style>") == .keyword)
        #expect(h.kind(of: "const", after: "</style>") == .keyword)
        #expect(h.kind(of: "1", after: "value: ") == .number)
    }

    @Test("blocks nested in JSX; <style> in strings, comments and templates isn't a block")
    func nestedBlocks() {
        let h = Highlighted(Self.nested, language: "stsx")
        #expect(h.kind(of: "border-radius") == .property, "\(h.dump)")
        #expect(h.kind(of: "$radius.lg") == .constant)
        #expect(h.kind(of: "$accent") == .constant)
        #expect(h.kind(of: "calc") == .function)
        #expect(h.kind(of: "$gap") == .constant)
        #expect(h.kind(of: "\"→ ✨ $notRef\"") == .string)
        #expect(h.kind(of: "/* $alsoNotRef */") == .comment)
        #expect(h.kind(of: "button", after: "</") == .tag)
        #expect(h.kind(of: "\"<style> in a string is not a block\"") == .string)
        #expect(h.kind(of: "// <style> in a comment is not a block either") == .comment)
        #expect(h.kind(of: "`<style>") == .string)
        #expect(h.kind(of: "export", after: "</style>`;\n") == .keyword)
        #expect(h.kind(of: "2", after: "count = ") == .number)
        let scan = StyleScan.scan(Self.nested as NSString)
        #expect(scan.blocks.count == 1)
        #expect(scan.references.map { (Self.nested as NSString).substring(with: $0) } == ["$radius.lg", "$accent", "$gap"])
    }

    @Test("Lumiose JSX (.sjsx)")
    func sjsx() {
        let h = Highlighted(Self.counter, language: "sjsx")
        #expect(h.kind(of: "signal", after: "= ") == .function, "\(h.dump)")
        #expect(h.kind(of: "button") == .tag)
        #expect(h.kind(of: "onClick") == .attribute)
        #expect(h.kind(of: "counter", after: "\n  .") == .property)
        #expect(h.kind(of: "$accent") == .constant)
        #expect(h.kind(of: "0.5") == .number)
    }

    @Test("an unclosed block runs to the end; the code before it is unaffected")
    func unclosedBlock() {
        let h = Highlighted("const a = 1;\n<style>\n  .x { color: $c; }\n", language: "stsx")
        #expect(h.kind(of: "const") == .keyword, "\(h.dump)")
        #expect(h.kind(of: "color") == .property)
        #expect(h.kind(of: "$c") == .constant)
        let scan = StyleScan.scan("a\n<style global data-x=\"a>b\">p{}</style >z" as NSString)
        #expect(scan.blocks.map(\.content) == [NSRange(location: 29, length: 3)])
        #expect(scan.blocks.map(\.range) == [NSRange(location: 2, length: 39)])
    }

    @Test("typing a closing tag or deleting an opening one re-highlights the code it reveals")
    func maskEdits() {
        let highlighter = SyntaxHighlighter(language: LanguageRegistry.language(id: "stsx")!)
        let source = "<style>\n.a { color: red; }\nconst x = 1;\n" as NSString
        highlighter.setText(source)
        let all = { (text: NSString) in highlighter.tokens(in: NSRange(location: 0, length: text.length)) }
        _ = all(source)
        // Close the block before `const`: the rest becomes TSX.
        let insertAt = source.range(of: "const").location
        let closed = NSMutableString(string: source)
        closed.insert("</style>\n", at: insertAt)
        let changed = highlighter.applyEdit(replacing: NSRange(location: insertAt, length: 0), with: 9, in: closed)
        let constRange = closed.range(of: "const")
        #expect(changed.contains { $0.location <= constRange.location && $0.upperBound >= constRange.upperBound }, "\(changed)")
        let fresh = SyntaxHighlighter(language: LanguageRegistry.language(id: "stsx")!)
        fresh.setText(closed.copy() as! NSString)
        #expect(all(closed) == fresh.tokens(in: NSRange(location: 0, length: closed.length)))
        #expect(all(closed).first { $0.range == constRange }?.kind == .keyword)
    }
}
