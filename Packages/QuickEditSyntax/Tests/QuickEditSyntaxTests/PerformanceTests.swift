import Foundation
import Testing

@testable import QuickEditSyntax

@Suite("Performance", .serialized)
struct PerformanceTests {
    /// About 10k lines of varied TypeScript.
    static let largeTypeScript: String = {
        let block = """
            /** Represents a user of the system. */
            export interface User {
              id: number;
              name: string;
              email?: string;
              roles: ReadonlyArray<"admin" | "editor" | "viewer">;
            }

            const MAX_USERS = 1_000;
            const pattern = /^[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}$/i;

            export class UserStore<T extends User = User> {
              private readonly users = new Map<number, T>();

              add(user: T): void {
                if (this.users.size >= MAX_USERS) {
                  throw new Error(`Too many users: ${this.users.size}`);
                }
                this.users.set(user.id, { ...user, name: user.name.trim() });
              }

              find(predicate: (user: T) => boolean): T | undefined {
                for (const user of this.users.values()) {
                  if (predicate(user)) return user; // early exit
                }
                return undefined;
              }
            }

            """
        let lines = block.components(separatedBy: "\n").count - 1
        return String(repeating: block, count: 10_000 / lines + 1)
    }()

    @Test("a screenful of a 10k-line TypeScript file highlights well under 16 ms")
    func screenful() throws {
        let text = Self.largeTypeScript as NSString
        let lineCount = text.components(separatedBy: "\n").count
        #expect(lineCount >= 10_000)
        let highlighter = SyntaxHighlighter(language: LanguageRegistry.language(id: "typescript")!)
        SyntaxHighlighter.prepare(highlighter.language)

        let clock = ContinuousClock()
        let parse = clock.measure { highlighter.setText(text) }

        // ~60 lines (about 2,000 UTF-16 units) at several positions, as the editor scrolls.
        var worst = Duration.zero
        var lineStarts: [Int] = [0]
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            lineStarts.append(enclosing.upperBound)
        }
        for startLine in stride(from: 0, to: lineCount - 60, by: 997) {
            let start = lineStarts[startLine]
            let end = lineStarts[min(startLine + 60, lineStarts.count - 1)]
            var tokens: [SyntaxToken] = []
            let elapsed = clock.measure { tokens = highlighter.tokens(in: NSRange(location: start, length: end - start)) }
            #expect(!tokens.isEmpty)
            worst = max(worst, elapsed)
        }

        // A keystroke in the middle: incremental reparse plus the visible tokens.
        let middle = lineStarts[lineCount / 2]
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: NSRange(location: middle, length: 0), with: "x")
        let keystroke = clock.measure {
            highlighter.applyEdit(replacing: NSRange(location: middle, length: 0), with: 1, in: mutable)
            _ = highlighter.tokens(in: NSRange(location: middle, length: 2_000))
        }

        print("PERF typescript lines=\(lineCount) units=\(text.length) initialParse=\(parse) worstScreenful=\(worst) keystroke=\(keystroke)")
        #expect(worst < Self.frameBudget, "screenful took \(worst)")
        #expect(keystroke < Self.frameBudget, "keystroke took \(keystroke)")
    }

    /// One frame in optimized builds (measured ~1 ms per screenful, ~3.5 ms per keystroke on Apple silicon); debug
    /// builds compile the parsers without optimization and run beside the other suites, so they only get a sanity
    /// bound.
    #if DEBUG
        static let frameBudget = Duration.milliseconds(100)
    #else
        static let frameBudget = Duration.milliseconds(16)
    #endif

    @Test("grammar loading (query compilation) times")
    func grammarLoadTimes() throws {
        let clock = ContinuousClock()
        var lines: [String] = []
        for name in VendoredGrammars.names {
            let elapsed = try clock.measure { _ = try GrammarConfiguration(name: name) }
            lines.append("\(name)=\(elapsed.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 1))))")
        }
        print("PERF grammar load: " + lines.joined(separator: " "))
    }
}
