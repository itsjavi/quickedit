import Foundation
import Testing

@testable import QuickEditSyntax

/// A tool for writing query overrides, not a check: prints the tokens of a file.
///
///     QE_DUMP=markdown:/path/to/file.md swift test --package-path Packages/QuickEditSyntax --filter dumpTokens
@Test(.enabled(if: ProcessInfo.processInfo.environment["QE_DUMP"] != nil))
func dumpTokens() throws {
    let argument = try #require(ProcessInfo.processInfo.environment["QE_DUMP"])
    let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
    try #require(parts.count == 2, "QE_DUMP must be <language id>:<path>")
    let highlighted = Highlighted(try String(contentsOfFile: parts[1], encoding: .utf8), language: parts[0])
    print(highlighted.dump)
}
