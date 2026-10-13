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
            dependencies: ["QuickEditCore"],
            path: "Tests/QuickEditCoreTests"
        ),
    ]
)
