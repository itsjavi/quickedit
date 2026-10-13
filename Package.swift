// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuickEdit",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "QuickEdit", targets: ["QuickEdit"]),
    ],
    dependencies: [
        // cmark-gfm: GitHub's Markdown engine (tables, task lists, autolinks, tagfilter).
        .package(url: "https://github.com/swiftlang/swift-cmark.git", from: "0.9.0"),
        // Language registry, vendored tree-sitter grammars and the highlighter (decision-2).
        .package(path: "Packages/QuickEditSyntax"),
    ],
    targets: [
        .target(
            name: "QuickEditCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            path: "Sources/QuickEditCore"
        ),
        .executableTarget(
            name: "QuickEdit",
            dependencies: ["QuickEditCore", .product(name: "QuickEditSyntax", package: "QuickEditSyntax")],
            path: "Sources/QuickEdit",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        // Quick Look preview extension, assembled into Contents/PlugIns/QuickEditQuickLook.appex by build-app.sh.
        .executableTarget(
            name: "QuickEditQuickLook",
            dependencies: ["QuickEditCore"],
            path: "Sources/QuickEditQuickLook",
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.unsafeFlags(["-application-extension", "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
        .testTarget(
            name: "QuickEditCoreTests",
            dependencies: ["QuickEditCore", .product(name: "QuickEditSyntax", package: "QuickEditSyntax")],
            path: "Tests/QuickEditCoreTests"
        ),
    ]
)
