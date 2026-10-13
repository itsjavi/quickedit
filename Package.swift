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
            dependencies: ["QuickEditCore"],
            path: "Sources/QuickEdit",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "QuickEditCoreTests",
            dependencies: ["QuickEditCore"],
            path: "Tests/QuickEditCoreTests"
        ),
    ]
)
