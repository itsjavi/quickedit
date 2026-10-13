import Foundation
import QuickEditCore
import Testing

/// Cases from git's t/t3070-wildmatch.sh, "pathmatch" column (WM_PATHNAME).
@Suite struct WildmatchTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let pattern: String
        let path: String
        let matches: Bool
        var testDescription: String { "\(pattern) \(matches ? "~" : "!~") \(path)" }
    }

    static let cases: [Case] = [
        Case(pattern: "foo", path: "foo", matches: true),
        Case(pattern: "foo", path: "bar", matches: false),
        Case(pattern: "", path: "", matches: true),
        Case(pattern: "???", path: "foo", matches: true),
        Case(pattern: "??", path: "foo", matches: false),
        Case(pattern: "*", path: "foo", matches: true),
        Case(pattern: "f*", path: "foo", matches: true),
        Case(pattern: "*f", path: "foo", matches: false),
        Case(pattern: "*foo*", path: "foo", matches: true),
        Case(pattern: "*ob*a*r*", path: "foobar", matches: true),
        Case(pattern: "*ab", path: "aaaaaaabababab", matches: true),
        Case(pattern: "foo\\*", path: "foo*", matches: true),
        Case(pattern: "foo\\*bar", path: "foobar", matches: false),
        Case(pattern: "f\\\\oo", path: "f\\oo", matches: true),
        Case(pattern: "*[al]?", path: "ball", matches: true),
        Case(pattern: "[ten]", path: "ten", matches: false),
        Case(pattern: "**[!te]", path: "ten", matches: true),
        Case(pattern: "**[!ten]", path: "ten", matches: false),
        Case(pattern: "t[a-g]n", path: "ten", matches: true),
        Case(pattern: "t[!a-g]n", path: "ten", matches: false),
        Case(pattern: "t[!a-g]n", path: "ton", matches: true),
        Case(pattern: "t[^a-g]n", path: "ton", matches: true),
        Case(pattern: "a[]]b", path: "a]b", matches: true),
        Case(pattern: "a[]-]b", path: "a-b", matches: true),
        Case(pattern: "a[]-]b", path: "a]b", matches: true),
        Case(pattern: "a[]-]b", path: "aab", matches: false),
        Case(pattern: "a[]a-]b", path: "aab", matches: true),
        Case(pattern: "]", path: "]", matches: true),
        Case(pattern: "foo*bar", path: "foo/baz/bar", matches: false),
        Case(pattern: "foo**bar", path: "foo/baz/bar", matches: false),
        Case(pattern: "foo/**/bar", path: "foo/baz/bar", matches: true),
        Case(pattern: "foo/**/bar", path: "foo/b/a/z/bar", matches: true),
        Case(pattern: "foo/**/**/bar", path: "foo/b/a/z/bar", matches: true),
        Case(pattern: "foo/**/bar", path: "foo/bar", matches: true),
        Case(pattern: "foo/**/**/bar", path: "foo/bar", matches: true),
        Case(pattern: "foo?bar", path: "foo/bar", matches: false),
        Case(pattern: "foo[/]bar", path: "foo/bar", matches: false),
        Case(pattern: "f[^eiu][^eiu][^eiu][^eiu][^eiu]r", path: "foo/bar", matches: false),
        Case(pattern: "**/foo", path: "foo", matches: true),
        Case(pattern: "**/foo", path: "XXX/foo", matches: true),
        Case(pattern: "**/foo", path: "bar/baz/foo", matches: true),
        Case(pattern: "*/foo", path: "bar/baz/foo", matches: false),
        Case(pattern: "**/bar*", path: "foo/bar/baz", matches: false),
        Case(pattern: "**/bar/*", path: "deep/foo/bar/baz", matches: true),
        Case(pattern: "**/bar/*", path: "deep/foo/bar/baz/", matches: false),
        Case(pattern: "**/bar/**", path: "deep/foo/bar/baz/", matches: true),
        Case(pattern: "**/bar/*", path: "deep/foo/bar", matches: false),
        Case(pattern: "**/bar/**", path: "deep/foo/bar/", matches: true),
        Case(pattern: "**/bar**", path: "foo/bar/baz", matches: false),
        Case(pattern: "*/bar/**", path: "foo/bar/baz/x", matches: true),
        Case(pattern: "*/bar/**", path: "deep/foo/bar/baz/x", matches: false),
        Case(pattern: "**/bar/*/*", path: "deep/foo/bar/baz/x", matches: true),
        Case(pattern: "[[:alpha:]][[:digit:]][[:upper:]]", path: "a1B", matches: true),
        Case(pattern: "[[:digit:][:upper:][:space:]]", path: "a", matches: false),
        Case(pattern: "[[:digit:][:upper:][:space:]]", path: "A", matches: true),
        Case(pattern: "[a-c[:digit:]x-z]", path: "5", matches: true),
        Case(pattern: "[a-c[:digit:]x-z]", path: "q", matches: false),
        Case(pattern: "-*-*-*-*-*-*-12-*-*-*-m-*-*-*", path: "-adobe-courier-bold-o-normal--12-120-75-75-m-70-iso8859-1", matches: true),
        Case(pattern: "XXX/*/*/*/*/*/*/12/*/*/*/m/*/*/*", path: "XXX/adobe/courier/bold/o/normal//12/120/75/75/m/70/iso8859/1", matches: true),
        Case(pattern: "**/*a*b*g*n*t", path: "abcd/abcdefg/abcdefghijk/abcdefghijklmnop.txt", matches: true),
        Case(pattern: "**/*a*b*g*n*t", path: "abcd/abcdefg/abcdefghijk/abcdefghijklmnop.txtz", matches: false),
        Case(pattern: "*/*/*", path: "foo/bba/arr", matches: true),
        Case(pattern: "*/*/*", path: "foo/bb/aa/rr", matches: false),
        Case(pattern: "**/**/**", path: "foo/bb/aa/rr", matches: true),
        Case(pattern: "*X*i", path: "abcXdefXghi", matches: true),
        Case(pattern: "*/*X*/*/*i", path: "ab/cXd/efXg/hi", matches: true),
        Case(pattern: "**/*X*/**/*i", path: "ab/cXd/efXg/hi", matches: true),
        Case(pattern: "abc/**", path: "abc", matches: false),
        Case(pattern: "abc/**", path: "abc/x/y", matches: true),
        Case(pattern: "a\\", path: "a", matches: false),
    ]

    @Test(arguments: cases)
    func wildmatch(_ testCase: Case) {
        #expect(GitIgnore.matches(pattern: testCase.pattern, path: testCase.path) == testCase.matches)
    }

    @Test func caseFolding() {
        #expect(GitIgnore.matches(pattern: "*.LOG", path: "a.log", ignoreCase: true))
        #expect(!GitIgnore.matches(pattern: "*.LOG", path: "a.log"))
        #expect(GitIgnore.matches(pattern: "[A-Z]x", path: "bx", ignoreCase: true))
        #expect(GitIgnore.matches(pattern: "[[:upper:]]x", path: "bx", ignoreCase: true))
    }
}

@Suite struct GitIgnoreFileTests {
    private func rules(_ contents: String, base: String = "", ignoreCase: Bool = false) -> GitIgnore {
        GitIgnore(contents: contents, base: base, ignoreCase: ignoreCase)
    }

    @Test func commentsBlankLinesAndEscapes() {
        let ignore = rules("# a comment\n\n*.log\n\\#hash\n\\!bang\n")
        #expect(ignore.isIgnored("a.log", isDirectory: false) == true)
        #expect(ignore.isIgnored("# a comment", isDirectory: false) == nil)
        #expect(ignore.isIgnored("#hash", isDirectory: false) == true)
        #expect(ignore.isIgnored("!bang", isDirectory: false) == true)
        #expect(ignore.isIgnored("bang", isDirectory: false) == nil)
    }

    @Test func trailingSpaces() {
        let ignore = rules("foo   \nbar\\ \n")
        #expect(ignore.isIgnored("foo", isDirectory: false) == true)
        #expect(ignore.isIgnored("foo   ", isDirectory: false) == nil)
        #expect(ignore.isIgnored("bar ", isDirectory: false) == true)
        #expect(ignore.isIgnored("bar", isDirectory: false) == nil)
    }

    @Test func negationAndLastMatchWins() {
        let ignore = rules("*.log\n!keep.log\n")
        #expect(ignore.isIgnored("x.log", isDirectory: false) == true)
        #expect(ignore.isIgnored("keep.log", isDirectory: false) == false)
        #expect(ignore.isIgnored("dir/keep.log", isDirectory: false) == false)
        let reversed = rules("!keep.log\n*.log\n")
        #expect(reversed.isIgnored("keep.log", isDirectory: false) == true)
    }

    @Test func directoryOnly() {
        let ignore = rules("build/\nfrotz/\ndoc/frotz/\n")
        #expect(ignore.isIgnored("build", isDirectory: true) == true)
        #expect(ignore.isIgnored("build", isDirectory: false) == nil)
        #expect(ignore.isIgnored("a/b/build", isDirectory: true) == true)
        #expect(ignore.isIgnored("a/frotz", isDirectory: true) == true)
        #expect(ignore.isIgnored("doc/frotz", isDirectory: true) == true)
        let anchoredOnly = rules("doc/frotz/\n")
        #expect(anchoredOnly.isIgnored("a/doc/frotz", isDirectory: true) == nil)
    }

    @Test func anchoring() {
        let ignore = rules("/top\nmid/name\nname-anywhere\n")
        #expect(ignore.isIgnored("top", isDirectory: false) == true)
        #expect(ignore.isIgnored("a/top", isDirectory: false) == nil)
        #expect(ignore.isIgnored("mid/name", isDirectory: false) == true)
        #expect(ignore.isIgnored("x/mid/name", isDirectory: false) == nil)
        #expect(ignore.isIgnored("x/y/name-anywhere", isDirectory: true) == true)
    }

    @Test func starSlashForms() {
        let ignore = rules("foo/*\n")
        #expect(ignore.isIgnored("foo/test.json", isDirectory: false) == true)
        #expect(ignore.isIgnored("foo/bar", isDirectory: true) == true)
        // Not matched by the pattern itself; IgnoreRules ignores it because foo/bar is.
        #expect(ignore.isIgnored("foo/bar/hello.c", isDirectory: false) == nil)
        let doubleStar = rules("**/logs\n**/cache/tmp\nabc/**\na/**/b\n")
        #expect(doubleStar.isIgnored("logs", isDirectory: true) == true)
        #expect(doubleStar.isIgnored("x/y/logs", isDirectory: true) == true)
        #expect(doubleStar.isIgnored("x/cache/tmp", isDirectory: false) == true)
        #expect(doubleStar.isIgnored("cache/tmp", isDirectory: false) == true)
        #expect(doubleStar.isIgnored("abc/x/y.txt", isDirectory: false) == true)
        #expect(doubleStar.isIgnored("abc", isDirectory: true) == nil)
        #expect(doubleStar.isIgnored("a/b", isDirectory: false) == true)
        #expect(doubleStar.isIgnored("a/x/y/b", isDirectory: false) == true)
    }

    @Test func patternsAreRelativeToTheirFolder() {
        let ignore = rules("/out\n*.tmp\nsub/deeper\n", base: "pkg")
        #expect(ignore.isIgnored("pkg/out", isDirectory: true) == true)
        #expect(ignore.isIgnored("out", isDirectory: true) == nil)
        #expect(ignore.isIgnored("pkg/x/out", isDirectory: true) == nil)
        #expect(ignore.isIgnored("pkg/x/y.tmp", isDirectory: false) == true)
        #expect(ignore.isIgnored("other/y.tmp", isDirectory: false) == nil)
        #expect(ignore.isIgnored("pkg/sub/deeper", isDirectory: false) == true)
        #expect(ignore.isIgnored("pkg", isDirectory: true) == nil)
        #expect(ignore.isIgnored("pkgx/a.tmp", isDirectory: false) == nil)
    }

    @Test func classesAndQuestionMarks() {
        let ignore = rules("file?.txt\n[a-c].md\n[!a-c].rst\n[[:digit:]]*.csv\n")
        #expect(ignore.isIgnored("file1.txt", isDirectory: false) == true)
        #expect(ignore.isIgnored("file10.txt", isDirectory: false) == nil)
        #expect(ignore.isIgnored("b.md", isDirectory: false) == true)
        #expect(ignore.isIgnored("d.md", isDirectory: false) == nil)
        #expect(ignore.isIgnored("d.rst", isDirectory: false) == true)
        #expect(ignore.isIgnored("a.rst", isDirectory: false) == nil)
        #expect(ignore.isIgnored("2024.csv", isDirectory: false) == true)
    }

    @Test func caseInsensitiveRepositories() {
        #expect(rules("*.LOG\nBuild/\n", ignoreCase: true).isIgnored("x/a.log", isDirectory: false) == true)
        #expect(rules("*.LOG\nBuild/\n", ignoreCase: true).isIgnored("build", isDirectory: true) == true)
        #expect(rules("*.LOG\n").isIgnored("a.log", isDirectory: false) == nil)
    }

    @Test func crlfFilesAndEmptyPatterns() {
        let ignore = rules("*.o\r\n!\r\n/\r\n\r\nbin/\r\n")
        #expect(ignore.isIgnored("main.o", isDirectory: false) == true)
        #expect(ignore.isIgnored("bin", isDirectory: true) == true)
        #expect(rules("# only comments\n\n").isEmpty)
    }

    @Test func everythingPattern() {
        #expect(rules("*\n").isIgnored("a/b/c", isDirectory: false) == true)
        #expect(rules("**\n").isIgnored("a/b/c", isDirectory: false) == true)
    }
}
