import AppKit
import Observation
import SwiftUI

/// Which rendered view a file gets.
enum PreviewKind {
    case markdown, html

    static func forFile(named name: String) -> PreviewKind? {
        switch (name as NSString).pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd", "mdx": .markdown
        case "html", "htm", "xhtml": .html
        default: nil
        }
    }
}

/// What a window's preview pane shows; fed from the editor's (unsaved) text.
@Observable final class PreviewModel {
    var text = ""
    var kind = PreviewKind.markdown
    var directory = FileManager.default.homeDirectoryForCurrentUser
    var allowsRemoteContent = false
    /// Source line to keep in view (split mode); nil leaves scrolling alone.
    var scrollLine: Int?
    @ObservationIgnored var onOpenFile: ((URL) -> Void)?
    @ObservationIgnored var onTranscribe: ((String) -> Void)?
}

struct DocumentPreview: View {
    let model: PreviewModel

    var body: some View {
        switch model.kind {
        case .markdown:
            MarkdownPreview(
                markdown: model.text,
                baseDirectory: model.directory,
                accessRoot: model.directory,
                allowsRemoteContent: model.allowsRemoteContent,
                scrollLine: model.scrollLine,
                onOpenFile: model.onOpenFile,
                onTranscribe: model.onTranscribe
            )
        case .html:
            HTMLPreview(html: model.text, directory: model.directory, allowsRemoteContent: model.allowsRemoteContent, onOpenFile: model.onOpenFile)
        }
    }
}
