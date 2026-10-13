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
    Grammar(target: "TreeSitterC", directory: "c", hasScanner: false),
    Grammar(target: "TreeSitterCPP", directory: "cpp", hasScanner: true),
    Grammar(target: "TreeSitterObjC", directory: "objc", hasScanner: false),
    Grammar(target: "TreeSitterCSharp", directory: "c_sharp", hasScanner: true),
    Grammar(target: "TreeSitterJava", directory: "java", hasScanner: false),
    Grammar(target: "TreeSitterKotlin", directory: "kotlin", hasScanner: true),
    Grammar(target: "TreeSitterPHP", directory: "php", hasScanner: true),
    Grammar(target: "TreeSitterRuby", directory: "ruby", hasScanner: true),
    Grammar(target: "TreeSitterLua", directory: "lua", hasScanner: true),
    Grammar(target: "TreeSitterSCSS", directory: "scss", hasScanner: true),
    Grammar(target: "TreeSitterSass", directory: "sass", hasScanner: true),
    Grammar(target: "TreeSitterVue", directory: "vue", hasScanner: true),
    Grammar(target: "TreeSitterSvelte", directory: "svelte", hasScanner: true),
    Grammar(target: "TreeSitterGraphQL", directory: "graphql", hasScanner: false),
    Grammar(target: "TreeSitterProto", directory: "proto", hasScanner: false),
    Grammar(target: "TreeSitterHCL", directory: "hcl", hasScanner: true),
    Grammar(target: "TreeSitterTerraform", directory: "terraform", hasScanner: true),
    Grammar(target: "TreeSitterZig", directory: "zig", hasScanner: false),
    Grammar(target: "TreeSitterDart", directory: "dart", hasScanner: true),
    Grammar(target: "TreeSitterPowerShell", directory: "powershell", hasScanner: true),
    Grammar(target: "TreeSitterGLSL", directory: "glsl", hasScanner: false),
    Grammar(target: "TreeSitterCMake", directory: "cmake", hasScanner: true),
    Grammar(target: "TreeSitterNix", directory: "nix", hasScanner: true),
    Grammar(target: "TreeSitterSpiceDB", directory: "spicedb", hasScanner: true),
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
