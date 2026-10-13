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
    /// The previewed text. Not observed itself: SwiftUI and the previews compared it with the last one on every
    /// keystroke, which took most of the time typing in a large Markdown file. Views follow `revision` instead.
    @ObservationIgnored var text = "" {
        didSet { revision &+= 1 }
    }
    private(set) var revision = 0
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
                revision: model.revision,
                baseDirectory: model.directory,
                accessRoot: model.directory,
                allowsRemoteContent: model.allowsRemoteContent,
                scrollLine: model.scrollLine,
                onOpenFile: model.onOpenFile,
                onTranscribe: model.onTranscribe
            )
        case .html:
            HTMLPreview(html: model.text, revision: model.revision, directory: model.directory, allowsRemoteContent: model.allowsRemoteContent, onOpenFile: model.onOpenFile)
        }
    }
}
