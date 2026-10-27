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

/// What happened to the file on disk that the window can't resolve by itself (shown in a bar above the editor).
enum DiskChange: String {
    /// Another app changed the file while this window has unsaved edits.
    case modified
    /// The file is gone; the text is still here and saving writes it back.
    case deleted
}

/// Per-document facts the status bar shows and changes.
@Observable final class EditorState {
    var line = 1
    var column = 1
    var selectionLength = 0
    var lineCount = 1
    var languageName = "Plain Text"
    /// Set when the user picked the language in the status bar; otherwise it follows the file name.
    var languageOverride: String?
    var indentation = Indentation(style: .spaces, width: 4)
    var indentationSource = IndentationSource.settings
    var encoding = TextEncoding.utf8
    var lineEnding = LineEnding.lf
    var hasMixedLineEndings = false
    var riskyCount = 0
    /// Name of the last hidden character the status bar revealed ("ZERO WIDTH SPACE U+200B").
    var lastRevealedRisky: String?
    /// Set when the file can't be saved back faithfully (lossy decoding, binary property list).
    var readOnlyReason: String?
    /// A binary property list shown as XML (read-only until converted).
    var isBinaryPropertyList = false
    /// What the file's `.editorconfig` files say (empty when there are none or they're turned off).
    var editorConfig = EditorConfigProperties()
    /// Markdown and HTML files get a preview and Edit / Split / Preview modes.
    var previewKind: PreviewKind?
    var mode = EditorMode.edit
    /// The preview's Remote Content toggle (this window only, off by default).
    var allowsRemoteContent = false
    /// CSV/TSV files can be edited as a table.
    var isTableAvailable = false
    /// A CSV/TSV file too large for Table mode (`EditorViewController.tableModeMaximumLength`).
    var isTableTooLarge = false
    var showsTable = false
    let voiceRecorder = VoiceRecorder()
    var showsVoiceRecorder = false
    /// Link destination of the clip being transcribed (shows the transcription sheet).
    var transcribeSource: String?
    /// The audio file behind `transcribeSource`.
    var transcribeURL: URL?
    var diskChange: DiskChange?

    var isReadOnly: Bool { readOnlyReason != nil }
}
