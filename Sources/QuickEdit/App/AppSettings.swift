import AppKit
import Observation

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// How a Markdown or HTML window shows its file.
enum EditorMode: String, CaseIterable, Identifiable {
    case edit, split, preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit: "Editor"
        case .split: "Split"
        case .preview: "Preview"
        }
    }

    var symbol: String {
        switch self {
        case .edit: "doc.plaintext"
        case .split: "rectangle.split.2x1"
        case .preview: "eye"
        }
    }
}

extension Notification.Name {
    /// Posted after any editor-facing setting changes; open editors reapply their configuration.
    static let editorSettingsDidChange = Notification.Name("QuickEditEditorSettingsDidChange")
}

/// App-wide preferences in `UserDefaults` (each build variant has its own domain).
@Observable final class AppSettings {
    static let shared = AppSettings()

    private nonisolated enum Key {
        static let appearance = "appearance"
        static let fontName = "fontName"
        static let fontSize = "fontSize"
        static let tabWidth = "tabWidth"
        static let indentWithTabs = "indentWithTabs"
        static let detectIndentation = "detectIndentation"
        static let showLineNumbers = "showLineNumbers"
        static let showInvisibles = "showInvisibles"
        static let wrapLines = "wrapLines"
        static let highlightCurrentLine = "highlightCurrentLine"
        static let trimTrailingWhitespace = "trimTrailingWhitespace"
        static let insertFinalNewline = "insertFinalNewline"
        static let useEditorConfig = "useEditorConfig"
        static let editorMode = "editorMode"
        /// Read by `TextDocument.autosavesInPlace`, so it applies from the next launch.
        static let autosaveInPlace = "autosaveInPlace"
    }

    private let defaults = UserDefaults.standard

    var appearance: AppearanceMode { didSet { store(appearance.rawValue, Key.appearance); applyAppearance() } }
    /// Empty: the system monospaced font.
    var fontName: String { didSet { store(fontName, Key.fontName) } }
    var fontSize: Double { didSet { store(fontSize, Key.fontSize) } }
    var tabWidth: Int { didSet { store(tabWidth, Key.tabWidth) } }
    var indentWithTabs: Bool { didSet { store(indentWithTabs, Key.indentWithTabs) } }
    var detectIndentation: Bool { didSet { store(detectIndentation, Key.detectIndentation) } }
    var showLineNumbers: Bool { didSet { store(showLineNumbers, Key.showLineNumbers) } }
    var showInvisibles: Bool { didSet { store(showInvisibles, Key.showInvisibles) } }
    var wrapLines: Bool { didSet { store(wrapLines, Key.wrapLines) } }
    var highlightCurrentLine: Bool { didSet { store(highlightCurrentLine, Key.highlightCurrentLine) } }
    var trimTrailingWhitespace: Bool { didSet { store(trimTrailingWhitespace, Key.trimTrailingWhitespace) } }
    var insertFinalNewline: Bool { didSet { store(insertFinalNewline, Key.insertFinalNewline) } }
    var useEditorConfig: Bool { didSet { store(useEditorConfig, Key.useEditorConfig) } }
    var editorMode: EditorMode { didSet { store(editorMode.rawValue, Key.editorMode) } }
    var autosaveInPlace: Bool { didSet { store(autosaveInPlace, Key.autosaveInPlace) } }

    /// The autosave mode this launch runs with (NSDocument expects a constant).
    nonisolated static let autosavesInPlaceThisLaunch = UserDefaults.standard.object(forKey: Key.autosaveInPlace) as? Bool ?? true

    private init() {
        defaults.register(defaults: [
            Key.appearance: AppearanceMode.system.rawValue,
            Key.fontName: "",
            Key.fontSize: 13.0,
            Key.tabWidth: 4,
            Key.indentWithTabs: false,
            Key.detectIndentation: true,
            Key.showLineNumbers: true,
            Key.showInvisibles: false,
            Key.wrapLines: true,
            Key.highlightCurrentLine: true,
            Key.trimTrailingWhitespace: false,
            Key.insertFinalNewline: false,
            Key.useEditorConfig: true,
            Key.editorMode: EditorMode.edit.rawValue,
            Key.autosaveInPlace: true,
        ])
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        fontName = defaults.string(forKey: Key.fontName) ?? ""
        fontSize = defaults.double(forKey: Key.fontSize)
        tabWidth = defaults.integer(forKey: Key.tabWidth)
        indentWithTabs = defaults.bool(forKey: Key.indentWithTabs)
        detectIndentation = defaults.bool(forKey: Key.detectIndentation)
        showLineNumbers = defaults.bool(forKey: Key.showLineNumbers)
        showInvisibles = defaults.bool(forKey: Key.showInvisibles)
        wrapLines = defaults.bool(forKey: Key.wrapLines)
        highlightCurrentLine = defaults.bool(forKey: Key.highlightCurrentLine)
        trimTrailingWhitespace = defaults.bool(forKey: Key.trimTrailingWhitespace)
        insertFinalNewline = defaults.bool(forKey: Key.insertFinalNewline)
        useEditorConfig = defaults.bool(forKey: Key.useEditorConfig)
        editorMode = EditorMode(rawValue: defaults.string(forKey: Key.editorMode) ?? "") ?? .edit
        autosaveInPlace = defaults.bool(forKey: Key.autosaveInPlace)
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .editorSettingsDidChange, object: self)
    }

    static let fontSizes: ClosedRange<Double> = 9...36

    var editorFont: NSFont {
        let size = CGFloat(min(max(fontSize, Self.fontSizes.lowerBound), Self.fontSizes.upperBound))
        if !fontName.isEmpty, let font = NSFont(name: fontName, size: size) { return font }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var defaultIndentation: Indentation {
        Indentation(style: indentWithTabs ? .tabs : .spaces, width: max(1, tabWidth))
    }

    func applyAppearance() {
        NSApp.appearance = appearance.appearance
    }
}
