import Foundation
import Observation

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

    var isReadOnly: Bool { readOnlyReason != nil }
}
