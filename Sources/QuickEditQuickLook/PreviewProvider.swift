import Foundation
import QuickEditCore
import QuickLookUI
import UniformTypeIdentifiers

/// Data-based Quick Look preview for text types macOS has no text preview for: `.ts`, which it types as MPEG-2
/// transport stream video, and YAML, TOML, CSS and Lumiose components, whose types conform only to `public.text`.
///
/// Text is shown as monospaced plain text, without syntax highlighting (decision-5). Real video is handed back to
/// Quick Look as the original file, so the system's movie preview still plays it.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        switch try TextPreviewDetection.classify(contentsOf: url) {
        case .text(let preview):
            let totalByteCount = preview.isTruncated ? try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize : nil
            let html = TextPreviewHTML.document(for: preview, totalByteCount: totalByteCount)
            return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 820, height: 640)) { reply in
                reply.stringEncoding = .utf8
                return Data(html.utf8)
            }
        case .transportStream:
            return QLPreviewReply(fileURL: url)
        case .binary:
            // Only movies have a system preview to fall back to; binary data named .yaml gets the generic one.
            if (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .movie) == true {
                return QLPreviewReply(fileURL: url)
            }
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}
