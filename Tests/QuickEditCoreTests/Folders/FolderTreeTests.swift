import Foundation
import QuickEditCore
import Testing

/// A throwaway folder tree under the temporary directory.
struct TempTree {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("quickedit-folders-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    @discardableResult
    func file(_ path: String, _ contents: String = "") throws -> URL {
        let url = url(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @discardableResult
    func folder(_ path: String) throws -> URL {
        let url = url(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func link(_ path: String, to destination: String) throws {
        try FileManager.default.createSymbolicLink(at: url(path), withDestinationURL: url(destination))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Suite struct IgnoreRulesTests {
    @Test func nestedFilesPrecedenceAndParents() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file(".gitignore", "*.log\nbuild/\n/top-only.txt\n!important.log\nnode_modules\nlogs/\n!logs/keep.txt\n")
        try tree.file("sub/.gitignore", "!keep.log\n*.tmp\n/local\n")
        for path in ["a.log", "important.log", "build/x.txt", "top-only.txt", "sub/top-only.txt", "sub/keep.log",
                     "sub/b.log", "sub/c.tmp", "c.tmp", "sub/local/f", "local/f", "node_modules/x/y.js", ".git/config",
                     "logs/keep.txt", "src/main.swift"] {
            try tree.file(path)
        }
        let rules = IgnoreRules(root: tree.root)
        func ignored(_ path: String, directory: Bool = false) -> Bool { rules.isIgnored(tree.url(path), isDirectory: directory) }

        #expect(ignored("a.log"))
        #expect(!ignored("important.log"))
        #expect(ignored("build", directory: true))
        #expect(ignored("build/x.txt"))
        #expect(ignored("top-only.txt"))
        #expect(!ignored("sub/top-only.txt"))
        #expect(!ignored("sub/keep.log"))  // the deeper file re-includes it
        #expect(ignored("sub/b.log"))
        #expect(ignored("sub/c.tmp"))
        #expect(!ignored("c.tmp"))  // sub's rules don't apply above it
        #expect(ignored("sub/local", directory: true))
        #expect(ignored("sub/local/f"))
        #expect(!ignored("local/f"))
        #expect(ignored("node_modules/x/y.js"))
        #expect(ignored(".git", directory: true))
        #expect(ignored(".git/config"))
        #expect(ignored("logs/keep.txt"))  // can't re-include a file inside an ignored folder
        #expect(!ignored("src/main.swift"))
        #expect(!rules.isIgnored(tree.root, isDirectory: true))
        #expect(!rules.isIgnored(URL(fileURLWithPath: "/elsewhere/a.log"), isDirectory: false))
    }

    @Test func gitDocsExcludeEverythingExceptFooBar() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file(".gitignore", "/*\n!/foo\n/foo/*\n!/foo/bar\n")
        let rules = IgnoreRules(root: tree.root)
        #expect(!rules.isIgnored(tree.url("foo"), isDirectory: true))
        #expect(!rules.isIgnored(tree.url("foo/bar/x.c"), isDirectory: false))
        #expect(rules.isIgnored(tree.url("foo/baz"), isDirectory: false))
        #expect(rules.isIgnored(tree.url("other"), isDirectory: true))
        #expect(rules.isIgnored(tree.url("other/file"), isDirectory: false))
    }

    @Test func infoExcludeAndIgnoreCaseFromTheRepository() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file(".git/config", "[core]\n\trepositoryformatversion = 0\n\tignorecase = true\n[remote \"origin\"]\n\tignorecase = false\n")
        try tree.file(".git/info/exclude", "*.secret\n")
        try tree.file(".gitignore", "!shared.secret\n*.LOG\n")
        let rules = IgnoreRules(root: tree.root)
        #expect(rules.isIgnored(tree.url("x.secret"), isDirectory: false))
        #expect(!rules.isIgnored(tree.url("shared.secret"), isDirectory: false))  // .gitignore beats info/exclude
        #expect(rules.isIgnored(tree.url("server.log"), isDirectory: false))
    }

    @Test func subfolderOfARepositoryUsesTheRulesAbove() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.folder(".git")
        try tree.file(".gitignore", "*.log\nbuild/\n/pkg/generated\n")
        let pkg = IgnoreRules(root: tree.url("pkg"))
        #expect(pkg.isIgnored(tree.url("pkg/a.log"), isDirectory: false))
        #expect(pkg.isIgnored(tree.url("pkg/generated"), isDirectory: true))
        #expect(!pkg.isIgnored(tree.url("pkg/src.swift"), isDirectory: false))
        // Opening an ignored folder still shows what's inside, minus what other rules ignore.
        let build = IgnoreRules(root: tree.url("build"))
        #expect(!build.isIgnored(tree.url("build/out.bin"), isDirectory: false))
        #expect(build.isIgnored(tree.url("build/debug.log"), isDirectory: false))
    }

    @Test func linkedWorktreeGitFile() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file("main/.git/info/exclude", "*.local\n")
        try tree.file("main/.git/worktrees/wt/commondir", "../..\n")
        try tree.file("wt/.git", "gitdir: ../main/.git/worktrees/wt\n")
        let rules = IgnoreRules(root: tree.url("wt"))
        #expect(rules.isIgnored(tree.url("wt/settings.local"), isDirectory: false))
        #expect(rules.isIgnored(tree.url("wt/.git"), isDirectory: false))
    }

    @Test func reloadPicksUpChanges() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file(".gitignore", "*.a\n")
        let rules = IgnoreRules(root: tree.root)
        #expect(rules.isIgnored(tree.url("x.a"), isDirectory: false))
        try tree.file(".gitignore", "*.b\n")
        #expect(rules.isIgnored(tree.url("x.a"), isDirectory: false))  // cached
        rules.reload()
        #expect(!rules.isIgnored(tree.url("x.a"), isDirectory: false))
        #expect(rules.isIgnored(tree.url("x.b"), isDirectory: false))
    }

    @Test func symlinkedPathsResolve() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file(".gitignore", "*.log\n")
        let rules = IgnoreRules(root: tree.root)
        // The temporary directory lives behind /var -> /private/var.
        let resolved = tree.url("a.log").resolvingSymlinksInPath()
        #expect(rules.isIgnored(resolved, isDirectory: false))
    }
}

@Suite struct FolderListingTests {
    @Test func orderAndFlags() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file(".gitignore", "build/\n*.log\n")
        try tree.file(".env")
        try tree.file("file10.txt")
        try tree.file("file2.txt")
        try tree.file("README.md")
        try tree.file("debug.log")
        try tree.folder("Sources")
        try tree.folder("build")
        try tree.folder(".git")
        try tree.folder("assets")
        var finderHidden = try tree.file("Icon.txt")
        var values = URLResourceValues()
        values.isHidden = true
        try finderHidden.setResourceValues(values)
        try tree.link("linked", to: "Sources")

        let entries = try FolderListing.children(of: tree.root, rules: IgnoreRules(root: tree.root))
        let names = entries.map(\.name)
        let folders = entries.prefix { $0.isDirectory }.map(\.name)
        #expect(Set(folders) == [".git", "assets", "build", "linked", "Sources"])
        #expect(entries.dropFirst(folders.count).allSatisfy { !$0.isDirectory })
        #expect(names.firstIndex(of: "assets")! < names.firstIndex(of: "Sources")!)
        #expect(names.firstIndex(of: "file2.txt")! < names.firstIndex(of: "file10.txt")!)

        func entry(_ name: String) -> FolderEntry { entries.first { $0.name == name }! }
        #expect(entry(".env").isHidden)
        #expect(entry("Icon.txt").isHidden)
        #expect(!entry("README.md").isHidden)
        #expect(entry("build").isIgnored)
        #expect(entry("debug.log").isIgnored)
        #expect(entry(".git").isIgnored)
        #expect(!entry("Sources").isIgnored)
        #expect(entry("linked").isDirectory)
        #expect(entry("README.md").url.standardizedFileURL == tree.url("README.md").standardizedFileURL)
    }

    @Test func childrenOfAnIgnoredFolderAreIgnored() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file(".gitignore", "build/\n")
        try tree.file("build/keep.txt")
        try tree.file("build/sub/x.o")
        let entries = try FolderListing.children(of: tree.url("build"), rules: IgnoreRules(root: tree.root))
        #expect(entries.map(\.name) == ["sub", "keep.txt"])
        #expect(entries.allSatisfy { $0.isIgnored })
    }

    @Test func nestedGitignoreAppliesToItsFolder() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file("pkg/.gitignore", "*.gen\n")
        try tree.file("pkg/a.gen")
        try tree.file("pkg/a.swift")
        try tree.file("b.gen")
        let rules = IgnoreRules(root: tree.root)
        let pkg = try FolderListing.children(of: tree.url("pkg"), rules: rules)
        #expect(pkg.first { $0.name == "a.gen" }?.isIgnored == true)
        #expect(pkg.first { $0.name == "a.swift" }?.isIgnored == false)
        let top = try FolderListing.children(of: tree.root, rules: rules)
        #expect(top.first { $0.name == "b.gen" }?.isIgnored == false)
    }

    @Test func withoutRulesNothingIsIgnored() throws {
        let tree = try TempTree()
        defer { tree.remove() }
        try tree.file(".gitignore", "*\n")
        try tree.file("a.txt")
        let entries = try FolderListing.children(of: tree.root, rules: nil)
        #expect(entries.allSatisfy { !$0.isIgnored })
        #expect(throws: (any Error).self) { try FolderListing.children(of: tree.url("missing"), rules: nil) }
    }
}

@Suite struct FolderIndexTests {
    private func makeTree() throws -> TempTree {
        let tree = try TempTree()
        try tree.file(".gitignore", "build/\n*.log\n")
        try tree.file("pkg/.gitignore", "generated/\n")
        for path in ["README.md", "Sources/App/main.swift", "Sources/App/View.swift", "Tests/AppTests.swift",
                     "build/out.bin", "debug.log", "pkg/lib.swift", "pkg/generated/api.swift", ".env",
                     ".github/workflows/ci.yml", ".git/HEAD", "Sources/.DS_Store"] {
            try tree.file(path)
        }
        try tree.link("link-to-readme", to: "README.md")
        try tree.link("link-to-sources", to: "Sources")
        return tree
    }

    @Test func skipsIgnoredHiddenAndGit() throws {
        let tree = try makeTree()
        defer { tree.remove() }
        let paths = try FolderIndex(root: tree.root, includeHidden: false, includeIgnored: false).build()
        #expect(paths == ["link-to-readme", "pkg/lib.swift", "README.md", "Sources/App/main.swift", "Sources/App/View.swift", "Tests/AppTests.swift"].sorted())
    }

    @Test func includesHiddenOrIgnoredWhenAsked() throws {
        let tree = try makeTree()
        defer { tree.remove() }
        let hidden = try FolderIndex(root: tree.root, includeHidden: true, includeIgnored: false).build()
        #expect(hidden.contains(".env"))
        #expect(hidden.contains(".github/workflows/ci.yml"))
        #expect(hidden.contains(".gitignore"))
        #expect(!hidden.contains(".git/HEAD"))
        #expect(!hidden.contains("debug.log"))
        let ignored = try FolderIndex(root: tree.root, includeHidden: false, includeIgnored: true).build()
        #expect(ignored.contains("build/out.bin"))
        #expect(ignored.contains("pkg/generated/api.swift"))
        #expect(ignored.contains("debug.log"))
        #expect(!ignored.contains(".env"))
        let everything = try FolderIndex(root: tree.root, includeHidden: true, includeIgnored: true).build()
        #expect(!everything.contains(".git/HEAD"))
        #expect(everything.count == 14)
    }

    @Test func limitAndCancellation() throws {
        let tree = try makeTree()
        defer { tree.remove() }
        #expect(try FolderIndex(root: tree.root, includeHidden: false, includeIgnored: false, limit: 2).build().count == 2)
        let index = FolderIndex(root: tree.root, includeHidden: false, includeIgnored: false)
        index.cancel()
        #expect(throws: CancellationError.self) { try index.build() }
    }

    @Test func subfolderOfARepository() throws {
        let tree = try makeTree()
        defer { tree.remove() }
        try tree.folder(".git")
        try tree.file("pkg/notes.log")
        let paths = try FolderIndex(root: tree.url("pkg"), includeHidden: false, includeIgnored: false).build()
        #expect(paths == ["lib.swift"])
    }
}
