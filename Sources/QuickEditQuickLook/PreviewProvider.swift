import Foundation
import QuickEditCore
import QuickLookUI
import UniformTypeIdentifiers

/// Data-based Quick Look preview for `.ts` files, which macOS types as MPEG-2 transport stream video.
///
/// TypeScript (and any other text) is shown as monospaced plain text. Real video, or other binary data, is handed back
/// to Quick Look as the original file, so the system's movie preview still plays it.
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
        case .transportStream, .binary:
            return QLPreviewReply(fileURL: url)
        }
    }
}
