// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuickEdit",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "QuickEdit", targets: ["QuickEdit"]),
    ],
    targets: [
        .target(
            name: "QuickEditCore",
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
