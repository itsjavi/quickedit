import Foundation
import Observation
import QuickEditCore

/// Where a document's indentation came from, shown in the status bar menu.
enum IndentationSource: String {
    case detected = "Detected from file"
    case editorConfig = ".editorconfig"
    case settings = "Settings default"
    case manual = "Set for this file"
}

/// Per-document facts the status bar shows and changes.
@Observable final class EditorState {
    var line = 1
    var column = 1
    var selectionLength = 0
    var lineCount = 1
    var languageName = "Plain Text"
    var indentation = Indentation(style: .spaces, width: 4)
    var indentationSource = IndentationSource.settings
    var encoding = TextEncoding.utf8
    var lineEnding = LineEnding.lf
    var hasMixedLineEndings = false
    var riskyCount = 0
    /// Set when the file can't be saved back faithfully (lossy decoding, binary property list).
    var readOnlyReason: String?
    /// Markdown and HTML files get a preview and Edit / Split / Preview modes.
    var previewKind: PreviewKind?
    var mode = EditorMode.edit
    /// The preview's Remote Content toggle (this window only, off by default).
    var allowsRemoteContent = false
    let voiceRecorder = VoiceRecorder()
    var showsVoiceRecorder = false
    /// Link destination of the clip being transcribed (shows the transcription sheet).
    var transcribeSource: String?
    /// The audio file behind `transcribeSource`.
    var transcribeURL: URL?

    var isReadOnly: Bool { readOnlyReason != nil }
}
