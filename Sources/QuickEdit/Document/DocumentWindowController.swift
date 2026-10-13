import AppKit

/// A document window: the editor (and, later, its preview) above the status bar. Windows join as native tabs.
final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    static let tabbingIdentifier = "QuickEditDocument"

    init(document: TextDocument) {
        let editor = EditorViewController(document: document)
        let window = NSWindow(contentViewController: editor)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.setContentSize(NSSize(width: 860, height: 640))
        window.contentMinSize = NSSize(width: 420, height: 240)
        super.init(window: window)
        shouldCascadeWindows = true
        window.delegate = self
        window.setFrameAutosaveName("QuickEditDocument")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        (contentViewController as? EditorViewController)?.tearDown()
    }
}
