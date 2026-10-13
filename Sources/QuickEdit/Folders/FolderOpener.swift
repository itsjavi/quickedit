import AppKit

/// Opening folders and the files in them (decision-6). A folder's windows are one native tab group: one tab per open
/// file, each with the folder's sidebar; a placeholder tab stands in while no file of the folder is open.
enum FolderOpener {
    static func openFolder(_ url: URL) {
        let model = FolderRegistry.model(for: url)
        NSDocumentController.shared.noteNewRecentDocumentURL(model.root)
        if let window = FolderRegistry.windows(of: model).first {
            present(window)
        } else {
            showPlaceholder(for: model)
        }
    }

    /// Opens `file` as a tab of the folder's group, or brings its tab forward.
    static func open(_ file: URL, in model: FolderModel) {
        if let document = NSDocumentController.shared.document(for: file) {
            document.showWindows()
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { _, _, error in
            if let error, Dialogs.shouldPresent(error) { NSApp.presentError(error) }
        }
    }

    static func showPlaceholder(for model: FolderModel) {
        let controller = FolderPlaceholderWindowController(model: model)
        placeholders.append(controller)
        if let window = controller.window { present(window) }
    }

    /// A document window of `model` is on screen: the placeholder tab isn't needed any more.
    static func documentWindowAppeared(in model: FolderModel) {
        for controller in placeholders where controller.model === model {
            controller.close()
        }
    }

    /// Keeps placeholder controllers alive while their windows are open.
    static var placeholders: [FolderPlaceholderWindowController] = []

    /// After a window of `model` closed: when it was the last one, the folder closes too.
    static func windowClosed(in model: FolderModel, closing window: NSWindow) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if FolderRegistry.windows(of: model).allSatisfy({ $0 === window }) { FolderRegistry.close(model) }
            }
        }
    }

    static func present(_ window: NSWindow) {
        if AppVariant.isBackground {
            NSApp.unhideWithoutActivation()
            window.orderBack(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Puts `window` in the tab group of a visible window with the same tabbing identifier (its folder, or plain files).
    static func joinTabGroup(_ window: NSWindow) {
        guard (window.tabbedWindows?.count ?? 1) <= 1,
              let host = NSApp.windows.first(where: { $0 !== window && $0.isVisible && $0.tabbingIdentifier == window.tabbingIdentifier })
        else { return }
        host.addTabbedWindow(window, ordered: .above)
    }
}

/// Sidebar + content for a window of a folder: the editor of one file, or the placeholder.
final class FolderSplitViewController: NSSplitViewController {
    let sidebar: FolderSidebarViewController

    init(model: FolderModel, content: NSViewController) {
        sidebar = FolderSidebarViewController(model: model)
        super.init(nibName: nil, bundle: nil)
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 420
        sidebarItem.canCollapse = true
        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: content))
        splitView.autosaveName = "QuickEditFolderSidebar"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// The tab a folder shows while none of its files is open.
final class FolderPlaceholderWindowController: NSWindowController, NSWindowDelegate {
    let model: FolderModel

    init(model: FolderModel) {
        self.model = model
        let placeholder = NSViewController()
        let label = NSTextField(wrappingLabelWithString: "Select a file in the sidebar, or press ⌘P to open one by name.")
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        let view = NSView()
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
        ])
        placeholder.view = view
        let split = FolderSplitViewController(model: model, content: placeholder)
        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.tabbingMode = .preferred
        window.tabbingIdentifier = model.tabbingIdentifier
        window.title = model.name
        window.representedURL = model.root
        window.isRestorable = false
        window.setContentSize(NSSize(width: 1000, height: 680))
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("QuickEditFolderWindow") { window.center() }
        window.setFrameAutosaveName("QuickEditFolderWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        FolderOpener.placeholders.removeAll { $0 === self }
        FolderOpener.windowClosed(in: model, closing: window)
    }
}
