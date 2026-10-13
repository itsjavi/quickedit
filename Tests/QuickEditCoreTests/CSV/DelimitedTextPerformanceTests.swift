import Foundation
import QuickEditCore
import Testing

/// TASK-17 budget: parsing a 5 MB CSV well under 300 ms in release. Debug builds get 10x;
/// `swift test -c release --filter DelimitedTextPerformance` checks the real budget.
@Suite(.serialized) struct DelimitedTextPerformanceTests {
    #if DEBUG
    static let slack = 10.0
    #else
    static let slack = 1.0
    #endif

    /// About 5 MB of CSV with CRLF rows, quoted fields, escaped quotes, multi-line cells and non-ASCII text.
    static let fiveMegabytes: String = {
        var rows: [String] = ["id,name,city,amount,note,date"]
        var size = 0
        var index = 0
        while size < 5_000_000 {
            let note = index % 10 == 0 ? "\"multi\r\nline, \"\"quoted\"\" note\"" : "plain note \(index)"
            let row = "\(index),\"Smith, J\(index)\",Zürich,\(index * 3).50,\(note),2026-10-\(index % 28 + 1)"
            rows.append(row)
            size += row.utf8.count + 2
            index += 1
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }()

    @Test func parsesFiveMegabytes() {
        for text in [NSMutableString(string: Self.fiveMegabytes), Self.fiveMegabytes as NSString] {
            var table: DelimitedText?
            let duration = (0..<3).map { _ in
                ContinuousClock().measure { table = DelimitedText.parse(text, delimiter: ",") }
            }.min()!
            let budget = Duration.milliseconds(300 * Self.slack)
            print("DelimitedText.parse 5 MB (\(type(of: text))): \(duration), \(table?.rows.count ?? 0) rows (budget \(budget))")
            #expect(duration < budget)
            #expect(table?.columnCount == 6)
            #expect(table?.value(row: 1, column: 4) == "multi\r\nline, \"quoted\" note")
        }
    }

    @Test func detectsTheDelimiterQuickly() {
        let text = Self.fiveMegabytes as NSString
        let duration = ContinuousClock().measure { #expect(DelimitedText.detectDelimiter(text, fileExtension: nil) == ",") }
        print("DelimitedText.detectDelimiter 5 MB: \(duration)")
        #expect(duration < .milliseconds(20 * Self.slack))
    }
}
