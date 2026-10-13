import QuickEditCore
import SwiftUI

/// The bar under the editor: caret position and warnings on the left; language, indentation, encoding and line
/// endings on the right, each a menu that changes it for this file.
struct StatusBarView: View {
    static let height: CGFloat = 24

    let state: EditorState
    weak var controller: EditorViewController?

    var body: some View {
        HStack(spacing: 16) {
            Text(position)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if state.riskyCount > 0 {
                Button {
                    controller?.revealNextRiskyCharacter(nil)
                } label: {
                    Label(state.riskyCount == 1 ? "1 hidden character" : "\(state.riskyCount) hidden characters", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .help("Invisible or look-alike characters (zero-width, bidirectional controls, unusual spaces) are marked in orange. Click to select the next one."
                    + (state.lastRevealedRisky.map { "\nSelected: \($0)" } ?? ""))
            }
            if state.isBinaryPropertyList {
                Button("Convert to XML") { controller?.document.convertPropertyListToXML(nil) }
                    .help("This is a binary property list shown as XML. Converting makes it editable; saving then writes an XML property list.")
            }
            if let reason = state.readOnlyReason {
                Label("Read Only", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
                    .help(reason)
            }
            Spacer(minLength: 8)
            if state.previewKind == .markdown, controller?.canRecordVoiceNote == true {
                VoiceNoteButton(recorder: state.voiceRecorder, showsPanel: Binding(get: { state.showsVoiceRecorder }, set: { state.showsVoiceRecorder = $0 })) {
                    controller?.recordVoiceNote(nil)
                }
                .labelStyle(.iconOnly)
            }
            if state.previewKind != nil {
                previewControls
            }
            indentationMenu
            encodingMenu
            lineEndingMenu
        }
        .font(.system(size: 11))
        .labelStyle(.titleAndIcon)
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .sheet(isPresented: Binding(get: { state.transcribeSource != nil && !Dialogs.isSuppressed }, set: { if !$0 { state.transcribeSource = nil } })) {
            if let source = state.transcribeSource, let audio = state.transcribeURL {
                TranscriptionSheet(audioURL: audio) { text in controller?.insertTranscript(text, forSource: source) }
            }
        }
    }

    private var position: String {
        var text = "Ln \(state.line), Col \(state.column)"
        if state.selectionLength > 0 { text += " (\(state.selectionLength) selected)" }
        return text
    }

    @ViewBuilder private var previewControls: some View {
        if state.mode != .edit {
            Toggle(isOn: Binding(get: { state.allowsRemoteContent }, set: { controller?.setAllowsRemoteContent($0) })) {
                Image(systemName: state.allowsRemoteContent ? "network" : "network.slash")
            }
            .toggleStyle(.button)
            .help(state.allowsRemoteContent
                ? "The preview loads remote images and stylesheets for this window. Click to block them again."
                : "The preview blocks remote images and stylesheets. Click to allow them for this window. Scripts never run.")
        }
        Picker("Mode", selection: Binding(get: { state.mode }, set: { controller?.setMode($0) })) {
            ForEach(EditorMode.allCases) { mode in
                Image(systemName: mode.symbol).help(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
        .fixedSize()
        .help("Editor, split or preview (⌘1, ⌘2, ⌘3)")
    }

    private var indentationMenu: some View {
        Menu {
            Picker("Indent Using", selection: Binding(
                get: { state.indentation.style },
                set: { style in controller?.setIndentation(Indentation(style: style, width: state.indentation.width)) }
            )) {
                Text("Spaces").tag(IndentStyle.spaces)
                Text("Tabs").tag(IndentStyle.tabs)
            }
            .pickerStyle(.inline)
            Picker(state.indentation.style == .tabs ? "Tab Width" : "Indent Width", selection: Binding(
                get: { state.indentation.width },
                set: { width in controller?.setIndentation(Indentation(style: state.indentation.style, width: width)) }
            )) {
                ForEach([2, 3, 4, 8], id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Convert Indentation to Spaces") {
                controller?.convertIndentation(to: Indentation(style: .spaces, width: state.indentation.width))
            }
            Button("Convert Indentation to Tabs") {
                controller?.convertIndentation(to: Indentation(style: .tabs, width: state.indentation.width))
            }
            Button("Detect from File") { controller?.detectIndentation() }
            Divider()
            Text("Source: \(state.indentationSource.rawValue)")
        } label: {
            Text(state.indentation.style == .tabs ? "Tab Size: \(state.indentation.width)" : "Spaces: \(state.indentation.width)")
        }
        .fixedSize()
        .help("Indentation for this file")
    }

    private var encodingMenu: some View {
        Menu {
            Section("Save with Encoding") {
                ForEach(TextEncoding.common, id: \.self) { encoding in
                    Toggle(encoding.displayName, isOn: Binding(
                        get: { state.encoding == encoding },
                        set: { _ in controller?.setSaveEncoding(encoding) }
                    ))
                }
            }
            Menu("Reopen with Encoding") {
                ForEach(TextEncoding.common, id: \.self) { encoding in
                    Button(encoding.displayName) { controller?.reopen(with: encoding) }
                }
            }
        } label: {
            Text(state.encoding.displayName)
        }
        .fixedSize()
        .help("Text encoding")
    }

    private var lineEndingMenu: some View {
        Menu {
            Section("Convert Line Endings To") {
                ForEach(LineEnding.allCases, id: \.self) { ending in
                    Toggle(ending.menuTitle, isOn: Binding(
                        get: { state.lineEnding == ending && !state.hasMixedLineEndings },
                        set: { _ in controller?.convertLineEndings(to: ending) }
                    ))
                }
            }
        } label: {
            if state.hasMixedLineEndings {
                Label("Mixed (\(state.lineEnding.displayName))", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Text(state.lineEnding.displayName)
            }
        }
        .fixedSize()
        .help(state.hasMixedLineEndings ? "This file mixes line endings; new lines use \(state.lineEnding.displayName)" : "Line endings")
    }
}

extension LineEnding {
    var menuTitle: String {
        switch self {
        case .lf: "LF (macOS, Linux)"
        case .crlf: "CRLF (Windows)"
        case .cr: "CR (classic Mac)"
        }
    }
}
