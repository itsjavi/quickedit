import AppKit

/// A document window: the editor (and its preview) above the status bar, with the folder's file tree as a sidebar
/// when the file is inside an open folder. Windows join as native tabs: plain files together, a folder's files in
/// the folder's group.
final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    static let tabbingIdentifier = "QuickEditDocument"
    private static let frameName = "QuickEditDocument"
    let folder: FolderModel?
    private let editor: EditorViewController

    init(document: TextDocument) {
        editor = EditorViewController(document: document)
        folder = FolderRegistry.folder(containing: document.fileURL)
        let window: NSWindow
        if let folder {
            window = NSWindow(contentViewController: FolderSplitViewController(model: folder, content: editor))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.tabbingIdentifier = folder.tabbingIdentifier
            window.subtitle = folder.name
            window.setContentSize(NSSize(width: 1000, height: 680))
        } else {
            window = NSWindow(contentViewController: editor)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.tabbingIdentifier = Self.tabbingIdentifier
            window.setContentSize(NSSize(width: 860, height: 640))
        }
        window.tabbingMode = .preferred
        window.contentMinSize = NSSize(width: 420, height: 240)
        // Restored windows come back in front: the background Test build starts with none.
        window.isRestorable = !AppVariant.isBackground
        super.init(window: window)
        // Files join the frontmost window as tabs, so new windows reuse the last frame instead of cascading
        // off it; the very first one is centred (a window made without a frame starts at the screen's corner).
        shouldCascadeWindows = false
        window.delegate = self
        let frameName = folder == nil ? Self.frameName : "QuickEditFolderWindow"
        if !window.setFrameUsingName(frameName) { window.center() }
        window.setFrameAutosaveName(frameName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: Unsaved-changes indicator

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        updateTabTitle()
    }

    /// Tabs show a dot before the name of a file with unsaved changes (the title bar already says "Edited").
    /// Called by the document after every change-count update, once AppKit has applied it.
    func updateTabTitle() {
        guard let window, let document = document as? NSDocument else { return }
        guard document.isDocumentEdited else {
            window.tab.attributedTitle = nil
            return
        }
        let title = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: NSColor.controlAccentColor])
        title.append(NSAttributedString(string: document.displayName ?? window.title))
        window.tab.attributedTitle = title
    }

    var sidebar: FolderSidebarViewController? { (contentViewController as? FolderSplitViewController)?.sidebar }

    func windowDidBecomeKey(_ notification: Notification) {
        if let url = (document as? NSDocument)?.fileURL { sidebar?.reveal(url, select: true) }
    }

    func windowWillClose(_ notification: Notification) {
        editor.tearDown()
        if let folder, let window { FolderOpener.windowClosed(in: folder, closing: window) }
    }
}
