import AVKit
import AppKit
import QuickEditCore
import QuickLookUI
import UniformTypeIdentifiers

/// View-based Quick Look preview for text types macOS has no text preview for: `.ts`, which it types as MPEG-2
/// transport stream video, and YAML, TOML, CSS and Lumiose components, whose types conform only to `public.text`.
///
/// A plain, selectable text view styled like the system's own text preview, so the space-bar preview and Finder's
/// preview pane (which ignores data-based previews) look the same as for `.txt` and `.md`. No syntax highlighting
/// (decision-5). Real video plays in a player view instead.
final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 640))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        switch try TextPreviewDetection.classify(contentsOf: url) {
        case .text(let preview):
            showText(preview, of: url)
        case .transportStream:
            showVideo(url)
        case .binary:
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private func showText(_ preview: TextPreview, of url: URL) {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .textColor
        var text = preview.text
        if preview.isTruncated {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            }
            text += "\n\n… Showing the first \(TextPreviewDetection.defaultByteLimit / 1024) KB" + (size.map { " of \($0)" } ?? "") + ". Open the file to see the rest."
        }
        textView.string = text
        view.addSubview(scrollView)
    }

    private func showVideo(_ url: URL) {
        let player = AVPlayerView(frame: view.bounds)
        player.autoresizingMask = [.width, .height]
        player.controlsStyle = .inline
        player.player = AVPlayer(url: url)
        view.addSubview(player)
    }
}
