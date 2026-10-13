import Foundation
import QuickEditCore
import Testing

/// The vendored Material Icon Theme subset (`Resources/MaterialIcons`) resolves names like VS Code, and every icon it
/// names is there.
@Suite struct MaterialIconThemeTests {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/MaterialIcons")

    nonisolated(unsafe) private static let theme = try! MaterialIconTheme(directory: directory)

    @Test(arguments: [
        ("index.ts", "typescript"), ("types.d.ts", "typescript-def"), ("App.tsx", "react_ts"), ("main.swift", "swift"),
        ("package.json", "nodejs"), ("README.md", "readme"), ("notes.md", "markdown"), (".gitignore", "git"),
        ("Dockerfile", "docker"), ("Makefile", "makefile"), ("data.json", "json"), ("cities.csv", "table"),
        ("Card.stsx", "quickedit-lumiose-tsx"), ("Card.sjsx", "quickedit-lumiose-jsx"), ("mystery.qqq", "file"),
    ])
    func fileIcons(name: String, icon: String) {
        #expect(Self.theme.fileIcon(named: name, light: false) == icon)
    }

    @Test func lightVariantsWinInLightAppearance() {
        #expect(Self.theme.fileIcon(named: "Cargo.toml", light: false) != Self.theme.fileIcon(named: "Cargo.toml", light: true))
        #expect(Self.theme.fileIcon(named: "config.toml", light: true) == "toml_light")
        #expect(Self.theme.fileIcon(named: "Card.stsx", light: true) == "quickedit-lumiose-tsx_light")
        // Without a light variant, light appearance uses the regular icon.
        #expect(Self.theme.fileIcon(named: "index.ts", light: true) == "typescript")
    }

    @Test func languageIsTheLastResort() {
        #expect(Self.theme.fileIcon(named: "deploy", languageID: "shellscript", light: false) == "console")
        #expect(Self.theme.fileIcon(named: "deploy", light: false) == "file")
        // The name wins over the language.
        #expect(Self.theme.fileIcon(named: "package.json", languageID: "shellscript", light: false) == "nodejs")
    }

    @Test func folderIcons() {
        #expect(Self.theme.folderIcon(named: "src", expanded: false, light: false) == "folder-src")
        #expect(Self.theme.folderIcon(named: "Src", expanded: true, light: false) == "folder-src-open")
        #expect(Self.theme.folderIcon(named: "anything-else", expanded: false, light: false) == "folder")
        #expect(Self.theme.folderIcon(named: "anything-else", expanded: true, light: false) == "folder-open")
    }

    @Test func everyIconIsVendored() {
        let present = Set((try? FileManager.default.contentsOfDirectory(atPath: Self.directory.appendingPathComponent("icons").path)) ?? [])
        let missing = Self.theme.iconIDs.filter { id in Self.theme.fileName(ofIcon: id).map { !present.contains($0) } ?? true }
        #expect(missing.isEmpty, "Missing icons: \(missing.sorted().prefix(20))")
        #expect(Self.theme.iconIDs.count > 200)  // the subset (subset.json), not one or two icons
    }
}
