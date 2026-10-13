import Foundation
import QuickEditCore
import Testing

/// TASK-25 budgets: index a 50k-file tree well under 1 s and match 50k candidates per keystroke under 16 ms, in
/// release; `swift test -c release --filter FoldersPerformance` checks them. Debug builds only get sanity bounds:
/// the matcher's inner loop runs about 100x slower unoptimized.
@Suite(.serialized) struct FoldersPerformanceTests {
    #if DEBUG
    static let slack = 10.0
    // A sanity bound only: shared CI runners took 1.13 s for the worst query unoptimized.
    static let matchBudget = Duration.seconds(5)
    #else
    static let slack = 1.0
    static let matchBudget = Duration.milliseconds(16)
    #endif

    private func best(of runs: Int, _ body: () throws -> Void) rethrows -> Duration {
        var results: [Duration] = []
        for _ in 0..<runs {
            let start = ContinuousClock.now
            try body()
            results.append(ContinuousClock.now - start)
        }
        return results.min()!
    }

    /// 50 modules × 20 folders × 50 files, plus 5,000 ignored build products and a hidden folder.
    private func makeTree() throws -> TempTree {
        let tree = try TempTree()
        try tree.file(".gitignore", "build/\n*.o\n")
        func touch(_ path: String) { close(open(path, O_CREAT | O_WRONLY, 0o644)) }
        let root = tree.root.path
        for module in 0..<50 {
            for folder in 0..<20 {
                let directory = "\(root)/Sources/Module\(module)/Feature\(folder)"
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                for file in 0..<50 { touch("\(directory)/File\(file)View.swift") }
                touch("\(directory)/obj.o")
            }
        }
        for folder in 0..<50 {
            let directory = "\(root)/build/out\(folder)"
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for file in 0..<100 { touch("\(directory)/artifact\(file).bin") }
        }
        try tree.file(".cache/state.json")
        return tree
    }

    @Test func indexFiftyThousandFiles() throws {
        let tree = try makeTree()
        defer { tree.remove() }
        var count = 0
        let duration = try best(of: 3) {
            count = try FolderIndex(root: tree.root, includeHidden: false, includeIgnored: false).build().count
        }
        print("FolderIndex.build 50k files: \(duration), \(count) paths (budget \(Duration.seconds(Self.slack)))")
        #expect(count == 50_000)
        #expect(duration < .seconds(Self.slack))

        let listing = try best(of: 3) {
            _ = try FolderListing.children(of: tree.url("Sources/Module0/Feature0"), rules: IgnoreRules(root: tree.root))
        }
        print("FolderListing.children 51 entries: \(listing)")
    }

    @Test func fuzzyMatchFiftyThousandCandidates() {
        let candidates = (0..<50_000).map { index in
            "Sources/Module\(index % 50)/Feature\(index / 50 % 20)/File\(index % 50)View\(index).swift"
        }
        let budget = Self.matchBudget
        for query in ["f", "fv", "mod3feat", "file4view", "src/m12/f3/fv.sw", "zzz", "sources"] {
            var results: [FuzzyMatcher.Match] = []
            let duration = best(of: 3) { results = FuzzyMatcher.match(query, in: candidates, limit: 50) }
            print("FuzzyMatcher.match \"\(query)\" over 50k: \(duration), \(results.count) results (budget \(budget))")
            #expect(duration < budget, "\(query)")
        }
    }
}
