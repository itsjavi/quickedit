import AppKit

/// A document window: the editor (and, later, its preview) above the status bar. Windows join as native tabs.
final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    static let tabbingIdentifier = "QuickEditDocument"
    private static let frameName = "QuickEditDocument"

    init(document: TextDocument) {
        let editor = EditorViewController(document: document)
        let window = NSWindow(contentViewController: editor)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.setContentSize(NSSize(width: 860, height: 640))
        window.contentMinSize = NSSize(width: 420, height: 240)
        // Restored windows come back in front: the background Test build starts with none.
        window.isRestorable = !AppVariant.isBackground
        super.init(window: window)
        // Files join the frontmost window as tabs, so new windows reuse the last frame instead of cascading
        // off it; the very first one is centred (a window made without a frame starts at the screen's corner).
        shouldCascadeWindows = false
        window.delegate = self
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        (contentViewController as? EditorViewController)?.tearDown()
    }
}
