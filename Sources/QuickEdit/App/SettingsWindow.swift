import AppKit
import QuickEditCore
import SwiftUI

enum SettingsWindow {
    static func make() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView())
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("Settings")
        return window
    }
}

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Font") {
                    HStack {
                        TextField("System Monospaced", text: $settings.fontName)
                            .frame(width: 170)
                        Stepper(value: $settings.fontSize, in: AppSettings.fontSizes, step: 1) {
                            Text("\(Int(settings.fontSize)) pt").monospacedDigit()
                        }
                    }
                }
                Toggle("Show line numbers", isOn: $settings.showLineNumbers)
                Toggle("Highlight current line", isOn: $settings.highlightCurrentLine)
                Toggle("Wrap lines", isOn: $settings.wrapLines)
                Toggle("Show invisible characters", isOn: $settings.showInvisibles)
            }
            Section {
                Picker("Indent using", selection: $settings.indentWithTabs) {
                    Text("Spaces").tag(false)
                    Text("Tabs").tag(true)
                }
                Picker("Tab width", selection: $settings.tabWidth) {
                    ForEach([2, 3, 4, 8], id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle("Detect indentation from each file", isOn: $settings.detectIndentation)
                Toggle("Follow .editorconfig files", isOn: $settings.useEditorConfig)
            } header: {
                Text("Indentation")
            } footer: {
                Text(".editorconfig settings win over detection, and detection over these defaults.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Trim trailing whitespace on save", isOn: $settings.trimTrailingWhitespace)
                Toggle("End files with a line break on save", isOn: $settings.insertFinalNewline)
                Toggle("Save changes automatically", isOn: $settings.autosaveInPlace)
            } header: {
                Text("Saving")
            } footer: {
                Text("With automatic saving off, ⌘S saves and closing asks about unsaved changes. Applies after relaunching QuickEdit.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
