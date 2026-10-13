import Foundation
import QuickEditCore
import Testing

/// Timing budgets from TASK-3, measured as the best of a few runs. Debug builds (the default `swift test`) get a
/// looser budget; `swift test -c release --filter TextPerformance` checks the real ones.
@Suite(.serialized) struct TextPerformanceTests {
    #if DEBUG
    static let slack = 10.0
    #else
    static let slack = 1.0
    #endif

    /// About 1 MB of indented, code-like text with CRLF endings and a risky character every 100 lines.
    static let megabyte: String = {
        var lines: [String] = []
        var size = 0
        var index = 0
        while size < 1_000_000 {
            let depth = index % 5
            var line = String(repeating: "    ", count: depth) + "let value\(index) = compute(\(index), \"héllo\") // comment"
            if index % 100 == 0 { line += "\u{200B}" }
            lines.append(line)
            size += line.utf8.count + 2
            index += 1
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }()

    private func best(of runs: Int = 5, _ body: () -> Void) -> Duration {
        (0..<runs).map { _ in ContinuousClock().measure(body) }.min()!
    }

    private func expect(_ duration: Duration, under milliseconds: Double, _ label: String) {
        let budget = Duration.milliseconds(milliseconds * Self.slack)
        print("\(label): \(duration) (budget \(budget))")
        #expect(duration < budget, "\(label) took \(duration)")
    }

    @Test func riskyScanOfAVisibleRange() {
        let text = NSMutableString(string: Self.megabyte)
        let range = NSRange(location: text.length / 2, length: 5_000)
        var found = 0
        let duration = best { found = RiskyCharacters.scan(text, in: range).count }
        #expect(found > 0)
        expect(duration, under: 1, "RiskyCharacters.scan 5k of 1 MB")
    }

    @Test func riskyCount() {
        let mutable = NSMutableString(string: Self.megabyte)
        let bridged = Self.megabyte as NSString
        var count = 0
        expect(best { count = RiskyCharacters.count(in: mutable) }, under: 20, "RiskyCharacters.count 1 MB (NSMutableString)")
        expect(best { count = RiskyCharacters.count(in: bridged) }, under: 20, "RiskyCharacters.count 1 MB (bridged String)")
        #expect(count > 0)
    }

    @Test func lineEndingDetection() {
        var info: LineEndingInfo?
        expect(best { info = LineEndings.detect(Self.megabyte) }, under: 50, "LineEndings.detect 1 MB")
        #expect(info?.dominant == .crlf)
    }

    @Test func indentationDetection() {
        var indentation: Indentation?
        expect(best { indentation = IndentationDetector.detect(Self.megabyte) }, under: 50, "IndentationDetector.detect 1 MB")
        #expect(indentation == .spaces(4))
    }
}
