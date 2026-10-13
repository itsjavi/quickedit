import Foundation
import QuickEditCore
import Testing

@Suite struct FuzzyMatcherTests {
    private func ranking(_ query: String, _ candidates: [String]) -> [String] {
        FuzzyMatcher.match(query, in: candidates, limit: candidates.count).map(\.path)
    }

    @Test func requiresASubsequence() {
        #expect(FuzzyMatcher.score("abc", "a/b/c") != nil)
        #expect(FuzzyMatcher.score("abc", "acb") == nil)
        #expect(FuzzyMatcher.score("abcd", "abc") == nil)
        #expect(ranking("xyz", ["abc", "x/y"]).isEmpty)
    }

    @Test func caseInsensitiveAndSpacesIgnored() {
        #expect(FuzzyMatcher.score("README", "docs/readme.md") != nil)
        #expect(FuzzyMatcher.score("rm", "docs/README.md") != nil)
        #expect(FuzzyMatcher.score("ma sw", "src/main.swift")?.matches == FuzzyMatcher.score("masw", "src/main.swift")?.matches)
    }

    @Test func fileNameBeatsFolderName() {
        #expect(ranking("main", ["main/src/other.swift", "src/main.swift"]) == ["src/main.swift", "main/src/other.swift"])
        #expect(ranking("view", ["Views/Sidebar/Outline.swift", "Sources/App/View.swift"]).first == "Sources/App/View.swift")
    }

    @Test func consecutiveBeatsScattered() {
        #expect(ranking("abc", ["src/xaxbxcx.txt", "src/xabcx.txt"]) == ["src/xabcx.txt", "src/xaxbxcx.txt"])
        #expect(ranking("edit", ["src/e_d_i_t.txt", "src/editor.txt"]).first == "src/editor.txt")
    }

    @Test func wordStartsBeatMiddles() {
        #expect(ranking("fb", ["src/fab.swift", "src/FooBar.swift"]).first == "src/FooBar.swift")
        #expect(ranking("fb", ["src/xfxb.swift", "src/foo_bar.swift"]).first == "src/foo_bar.swift")
        #expect(ranking("sv", ["Sources/StatusView.swift", "Sources/Status/aaaaav.swift"]).first == "Sources/StatusView.swift")
    }

    @Test func tiesPreferShorterPaths() {
        #expect(ranking("readme", ["docs/README.md", "README.md"]) == ["README.md", "docs/README.md"])
    }

    @Test func pathQueries() {
        let candidates = ["Sources/QuickEdit/App/AppDelegate.swift", "Sources/QuickEditCore/Text/TextCodec.swift", "Tests/QuickEditCoreTests/Text/TextCodecTests.swift"]
        #expect(ranking("core/textcodec", candidates).first == "Sources/QuickEditCore/Text/TextCodec.swift")
        #expect(ranking("tests/codec", candidates).first == "Tests/QuickEditCoreTests/Text/TextCodecTests.swift")
    }

    @Test func matchedOffsets() {
        #expect(FuzzyMatcher.score("msw", "src/main.swift")?.matches == [4, 9, 10])
        #expect(FuzzyMatcher.score("main", "src/main.swift")?.matches == [4, 5, 6, 7])
        // UTF-16 offsets after non-ASCII folders.
        #expect(FuzzyMatcher.score("main", "café/😀/main.swift")?.matches == [8, 9, 10, 11])
        #expect(FuzzyMatcher.score("é", "café.txt")?.matches == [3])
    }

    @Test func limitAndEmptyQuery() {
        let candidates = (0..<100).map { "file\($0).txt" }
        #expect(FuzzyMatcher.match("file", in: candidates, limit: 10).count == 10)
        #expect(FuzzyMatcher.match("", in: candidates, limit: 3).map(\.path) == ["file0.txt", "file1.txt", "file2.txt"])
        #expect(FuzzyMatcher.match("file", in: candidates, limit: 0).isEmpty)
        let results = FuzzyMatcher.match("f", in: candidates, limit: 100)
        #expect(zip(results, results.dropFirst()).allSatisfy { $0.score >= $1.score })
    }

    @Test func matchAndScoreAgree() {
        let candidates = ["Sources/QuickEdit/Editor/EditorView.swift", "README.md", "Package.swift", "Sources/QuickEditCore/CSV/DelimitedText.swift"]
        for query in ["ed", "pkg", "csvdt", "e"] {
            for result in FuzzyMatcher.match(query, in: candidates, limit: 10) {
                #expect(FuzzyMatcher.score(query, result.path) == result)
                #expect(result.matches.count == query.count)
            }
        }
    }
}
