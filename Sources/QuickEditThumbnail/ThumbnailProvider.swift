import AVFoundation
import Foundation
import QuickEditCore
import QuickLookThumbnailing

/// Quick Look thumbnails for text types macOS has no thumbnail for (YAML, TOML, CSS, Lumiose components) and for `.ts`,
/// which macOS types as MPEG-2 transport stream video: the first lines on a page, so Finder's icons, preview pane and
/// gallery view show the content.
///
/// A real `.ts` video gets a frame from AVFoundation instead, as the system's movie thumbnail would show.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let url = request.fileURL
        let result: TextPreviewDetection.Result
        do {
            result = try TextPreviewDetection.classify(contentsOf: url, byteLimit: TextThumbnail.byteLimit)
        } catch {
            handler(nil, error)
            return
        }
        switch result {
        case .text(let preview):
            let lines = TextThumbnail.lines(of: preview.text)
            let reply = QLThumbnailReply(contextSize: TextThumbnail.pageSize(fitting: request.maximumSize)) { context in
                TextThumbnail.draw(lines, in: context, rect: context.boundingBoxOfClipPath)
                return true
            }
            reply.extensionBadge = url.pathExtension.uppercased()
            handler(reply, nil)
        case .transportStream, .binary:
            provideVideoFrame(for: request, handler)
        }
    }

    private func provideVideoFrame(
        for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let maximumSize = request.maximumSize
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: request.fileURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumSize.width * request.scale, height: maximumSize.height * request.scale)
        // Any frame near the one-second mark: short clips and sparse keyframes still get one.
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        nonisolated(unsafe) let handler = handler
        generator.generateCGImageAsynchronously(for: CMTime(seconds: 1, preferredTimescale: 600)) { image, _, error in
            guard let image else {
                handler(nil, error ?? CocoaError(.fileReadCorruptFile))
                return
            }
            let imageSize = CGSize(width: image.width, height: image.height)
            let size = AVMakeRect(aspectRatio: imageSize, insideRect: CGRect(origin: .zero, size: maximumSize)).size
            handler(QLThumbnailReply(contextSize: size) { context in
                context.draw(image, in: context.boundingBoxOfClipPath)
                return true
            }, nil)
        }
    }
}
