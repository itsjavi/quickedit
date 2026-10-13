// swift-tools-version: 6.2
// QuickEditSyntax: language registry, vendored tree-sitter grammars and the highlighter API (UI-free).
// Grammars are pinned in grammars.json and re-vendored with scripts/vendor-grammars.sh (`make grammars`).

import PackageDescription

struct Grammar {
    let target: String
    let directory: String
    let hasScanner: Bool
}

// BEGIN GENERATED GRAMMARS (scripts/vendor-grammars.sh)
let grammars: [Grammar] = [
    Grammar(target: "TreeSitterJavaScript", directory: "javascript", hasScanner: true),
    Grammar(target: "TreeSitterTypeScript", directory: "typescript", hasScanner: true),
    Grammar(target: "TreeSitterTSX", directory: "tsx", hasScanner: true),
    Grammar(target: "TreeSitterCSS", directory: "css", hasScanner: true),
    Grammar(target: "TreeSitterHTML", directory: "html", hasScanner: true),
    Grammar(target: "TreeSitterMarkdown", directory: "markdown", hasScanner: true),
    Grammar(target: "TreeSitterMarkdownInline", directory: "markdown_inline", hasScanner: true),
    Grammar(target: "TreeSitterJSON", directory: "json", hasScanner: false),
    Grammar(target: "TreeSitterYAML", directory: "yaml", hasScanner: true),
    Grammar(target: "TreeSitterTOML", directory: "toml", hasScanner: true),
    Grammar(target: "TreeSitterGo", directory: "go", hasScanner: false),
    Grammar(target: "TreeSitterGoMod", directory: "gomod", hasScanner: false),
    Grammar(target: "TreeSitterRust", directory: "rust", hasScanner: true),
    Grammar(target: "TreeSitterPython", directory: "python", hasScanner: true),
    Grammar(target: "TreeSitterSwift", directory: "swift", hasScanner: true),
    Grammar(target: "TreeSitterGDScript", directory: "gdscript", hasScanner: true),
    Grammar(target: "TreeSitterGodotResource", directory: "godot_resource", hasScanner: true),
    Grammar(target: "TreeSitterGDShader", directory: "gdshader", hasScanner: false),
    Grammar(target: "TreeSitterDockerfile", directory: "dockerfile", hasScanner: true),
    Grammar(target: "TreeSitterXML", directory: "xml", hasScanner: true),
    Grammar(target: "TreeSitterDTD", directory: "dtd", hasScanner: true),
    Grammar(target: "TreeSitterINI", directory: "ini", hasScanner: false),
    Grammar(target: "TreeSitterBash", directory: "bash", hasScanner: true),
    Grammar(target: "TreeSitterMake", directory: "make", hasScanner: false),
    Grammar(target: "TreeSitterSQL", directory: "sql", hasScanner: true),
    Grammar(target: "TreeSitterGitIgnore", directory: "gitignore", hasScanner: false),
    Grammar(target: "TreeSitterGitAttributes", directory: "gitattributes", hasScanner: false),
    Grammar(target: "TreeSitterDiff", directory: "diff", hasScanner: false),
]
// END GENERATED GRAMMARS

let grammarTargets: [Target] = grammars.map { grammar in
    .target(
        name: grammar.target,
        path: "Vendor/\(grammar.directory)",
        sources: grammar.hasScanner ? ["src/parser.c", "src/scanner.c"] : ["src/parser.c"],
        publicHeadersPath: "include",
        // Generated parsers and upstream scanners: their warnings aren't actionable here.
        cSettings: [.headerSearchPath("src"), .unsafeFlags(["-w"])]
    )
}

let package = Package(
    name: "QuickEditSyntax",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "QuickEditSyntax", targets: ["QuickEditSyntax"])
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", .upToNextMinor(from: "0.10.0"))
    ],
    targets: grammarTargets + [
        .target(
            name: "QuickEditSyntax",
            dependencies: [.product(name: "SwiftTreeSitter", package: "SwiftTreeSitter")]
                + grammars.map { .target(name: $0.target) }
        ),
        .testTarget(
            name: "QuickEditSyntaxTests",
            dependencies: ["QuickEditSyntax", .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter")]
        ),
    ],
    cLanguageStandard: .c11
)
