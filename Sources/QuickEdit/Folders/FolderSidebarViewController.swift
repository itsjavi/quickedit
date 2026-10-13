import AppKit
import QuickEditCore
import UniformTypeIdentifiers

/// A node of the file tree. NSOutlineView needs stable object identity per item, so nodes are cached by URL.
final class FolderNode: NSObject {
    let url: URL
    let entry: FolderEntry

    init(_ entry: FolderEntry) {
        url = entry.url.standardizedFileURL
        self.entry = entry
    }
}

/// The folder's file tree in a window's sidebar. Every window of the folder has one, all showing the same
/// `FolderModel` (expansion, filters); a single click opens a file as a tab of the group.
final class FolderSidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    let model: FolderModel
    private let outlineView = NSOutlineView()
    /// One image for every folder row, so its tinted rendering is made once, not per row and tab.
    private static let folderImage = NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder")
    private var nodes: [URL: FolderNode] = [:]
    private var isSyncingExpansion = false
    /// The tree changed while this sidebar's tab wasn't on screen: it reloads when shown.
    private var needsReload = false

    init(model: FolderModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowSizeStyle = .small
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(clicked(_:))
        outlineView.autosaveExpandedItems = false
        outlineView.registerForDraggedTypes([.fileURL])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        // The first width of the sidebar, until the user resizes it (the split view remembers that).
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 230, height: 600))
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        view = scrollView
        NotificationCenter.default.addObserver(self, selector: #selector(modelDidChange(_:)), name: .folderModelDidChange, object: model)
        NotificationCenter.default.addObserver(self, selector: #selector(expansionChanged(_:)), name: .folderExpansionDidChange, object: model)
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged(_:)), name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        reload()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// The only column fills the sidebar, so names use all of its width (not the column's default 100 pt).
    override func viewDidLayout() {
        super.viewDidLayout()
        outlineView.sizeLastColumnToFit()
    }

    // MARK: Data

    private func node(for entry: FolderEntry) -> FolderNode {
        let key = entry.url.standardizedFileURL
        if let existing = nodes[key], existing.entry == entry { return existing }
        let node = FolderNode(entry)
        nodes[key] = node
        return node
    }

    private func children(of item: Any?) -> [FolderEntry] {
        let folder = (item as? FolderNode)?.url ?? model.root
        return model.children(of: folder)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        node(for: children(of: item)[index])
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FolderNode)?.entry.isDirectory ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FolderNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            // Frames and autoresizing, not constraints: a new tab builds every visible row of its sidebar, and
            // Auto Layout made that a large part of opening a file.
            let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
            cell.identifier = identifier
            let image = NSImageView(frame: NSRect(x: 2, y: 3, width: 16, height: 16))
            image.autoresizingMask = [.minYMargin, .maxYMargin]
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingMiddle
            text.frame = NSRect(x: 23, y: 3, width: 175, height: 16)
            text.autoresizingMask = [.width, .minYMargin, .maxYMargin]
            cell.addSubview(image)
            cell.addSubview(text)
            cell.imageView = image
            cell.textField = text
            return cell
        }()
        cell.textField?.stringValue = node.entry.name
        cell.imageView?.image = node.entry.isDirectory
            ? Self.folderImage
            : NSWorkspace.shared.icon(for: UTType(filenameExtension: node.url.pathExtension) ?? .plainText)
        cell.imageView?.contentTintColor = node.entry.isDirectory ? .controlAccentColor : nil
        let dimmed = node.entry.isHidden || node.entry.isIgnored
        cell.alphaValue = dimmed ? 0.5 : 1
        cell.toolTip = node.entry.isIgnored ? "Ignored by .gitignore" : nil
        return cell
    }

    // MARK: Expansion and reloads

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isSyncingExpansion, let node = notification.userInfo?["NSObject"] as? FolderNode else { return }
        model.expanded.insert(node.url)
        NotificationCenter.default.post(name: .folderExpansionDidChange, object: model)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isSyncingExpansion, let node = notification.userInfo?["NSObject"] as? FolderNode else { return }
        model.expanded.remove(node.url)
        NotificationCenter.default.post(name: .folderExpansionDidChange, object: model)
    }

    /// Reloads only the folders that changed, and only in tabs on screen: with many tabs open, one change otherwise
    /// rebuilt every tab's tree.
    @objc private func modelDidChange(_ notification: Notification) {
        guard isShown else {
            needsReload = true
            return
        }
        if !needsReload, let folders = notification.userInfo?[FolderModel.changedFoldersKey] as? Set<URL>,
           !folders.contains(model.root.standardizedFileURL) {
            reload(folders)
        } else {
            reload()
        }
    }

    /// On screen: the window is visible, not minimized, covered or a tab in the background.
    private var isShown: Bool {
        view.window?.occlusionState.contains(.visible) == true
    }

    @objc private func occlusionChanged(_ notification: Notification) {
        guard notification.object as? NSWindow === view.window, isShown else { return }
        reloadIfNeeded()
    }

    /// Catches up with changes made while the tab was hidden.
    func reloadIfNeeded() {
        if needsReload { reload() }
    }

    @objc private func expansionChanged(_ notification: Notification) {
        applyExpansion()
    }

    /// Re-reads the tree, keeping expansion (shared) and the selection.
    func reload() {
        needsReload = false
        let selected = (outlineView.item(atRow: outlineView.selectedRow) as? FolderNode)?.url
        outlineView.reloadData()
        applyExpansion()
        if let selected { restoreSelection(selected) }
    }

    /// Re-reads the children of `folders` that are in the tree now.
    private func reload(_ folders: Set<URL>) {
        let selected = (outlineView.item(atRow: outlineView.selectedRow) as? FolderNode)?.url
        var reloaded = false
        for folder in folders {
            guard let node = nodes[folder], outlineView.row(forItem: node) >= 0 else { continue }
            outlineView.reloadItem(node, reloadChildren: true)
            reloaded = true
        }
        guard reloaded else { return }
        applyExpansion()
        if let selected { restoreSelection(selected) }
    }

    private func applyExpansion() {
        isSyncingExpansion = true
        defer { isSyncingExpansion = false }
        // Parents before children: rows only exist once their parent is expanded.
        var row = 0
        while row < outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? FolderNode, node.entry.isDirectory {
                let shouldExpand = model.expanded.contains(node.url)
                if shouldExpand != outlineView.isItemExpanded(node) {
                    if shouldExpand { outlineView.expandItem(node) } else { outlineView.collapseItem(node) }
                }
            }
            row += 1
        }
    }

    /// Selects `url` again after a reload when its row is still there, without scrolling to it.
    private func restoreSelection(_ url: URL) {
        guard let node = nodes[url.standardizedFileURL] else { return }
        let row = outlineView.row(forItem: node)
        if row >= 0, row != outlineView.selectedRow { outlineView.selectRowIndexes([row], byExtendingSelection: false) }
    }

    /// Expands the parents of `url` and scrolls to it (the window's file).
    func reveal(_ url: URL, select: Bool) {
        let target = url.standardizedFileURL
        guard model.contains(target) else { return }
        var parents: [URL] = []
        var current = target.deletingLastPathComponent()
        while model.contains(current), current.path.count >= model.root.path.count {
            parents.insert(current, at: 0)
            if current.path == model.root.path { break }
            current = current.deletingLastPathComponent()
        }
        model.expanded.formUnion(parents)
        applyExpansion()
        for row in 0..<outlineView.numberOfRows where (outlineView.item(atRow: row) as? FolderNode)?.url == target {
            if select { outlineView.selectRowIndexes([row], byExtendingSelection: false) }
            outlineView.scrollRowToVisible(row)
            return
        }
    }

    var selectedURL: URL? { (outlineView.item(atRow: outlineView.selectedRow) as? FolderNode)?.url }
    var clickedURL: URL? { outlineView.clickedRow >= 0 ? (outlineView.item(atRow: outlineView.clickedRow) as? FolderNode)?.url : nil }

    /// Rows as "indent name" lines (Test-build state dumps).
    var visibleRows: [String] {
        (0..<outlineView.numberOfRows).compactMap { row in
            guard let node = outlineView.item(atRow: row) as? FolderNode else { return nil }
            return String(repeating: "  ", count: outlineView.level(forRow: row)) + node.entry.name + (node.entry.isDirectory ? "/" : "")
        }
    }

    // MARK: Opening

    @objc private func clicked(_ sender: Any?) {
        guard let node = outlineView.item(atRow: outlineView.clickedRow) as? FolderNode else { return }
        if node.entry.isDirectory {
            if outlineView.isItemExpanded(node) { outlineView.animator().collapseItem(node) } else { outlineView.animator().expandItem(node) }
        } else {
            FolderOpener.open(node.url, in: model)
        }
    }

    // MARK: Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let target = clickedURL
        func add(_ title: String, _ action: Selector) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = target
        }
        add("New File…", #selector(newFile(_:)))
        add("New Folder…", #selector(newFolder(_:)))
        if target != nil {
            menu.addItem(.separator())
            add("Rename…", #selector(rename(_:)))
            add("Move to Trash", #selector(trash(_:)))
            menu.addItem(.separator())
            add("Reveal in Finder", #selector(reveal(_:)))
            add("Copy Path", #selector(copyPath(_:)))
        }
        menu.addItem(.separator())
        let toggle = menu.addItem(withTitle: "Show Hidden and Ignored Files", action: #selector(toggleHidden(_:)), keyEquivalent: "")
        toggle.target = self
        toggle.state = model.showsHiddenAndIgnored ? .on : .off
    }

    /// The folder new items go into: the clicked/selected folder, or the clicked file's folder, else the root.
    private func destinationFolder(for url: URL?) -> URL {
        guard let url else { return model.root }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue ? url : url.deletingLastPathComponent()
    }

    @objc func newFile(_ sender: NSMenuItem?) {
        FolderFileOperations.newItem(in: destinationFolder(for: (sender?.representedObject as? URL) ?? selectedURL), isFolder: false, model: model, window: view.window)
    }

    @objc func newFolder(_ sender: NSMenuItem?) {
        FolderFileOperations.newItem(in: destinationFolder(for: (sender?.representedObject as? URL) ?? selectedURL), isFolder: true, model: model, window: view.window)
    }

    @objc func rename(_ sender: NSMenuItem?) {
        guard let url = (sender?.representedObject as? URL) ?? selectedURL else { return }
        FolderFileOperations.rename(url, model: model, window: view.window)
    }

    @objc func trash(_ sender: NSMenuItem?) {
        guard let url = (sender?.representedObject as? URL) ?? selectedURL else { return }
        FolderFileOperations.trash(url, model: model)
    }

    @objc func reveal(_ sender: NSMenuItem?) {
        guard let url = (sender?.representedObject as? URL) ?? selectedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func copyPath(_ sender: NSMenuItem?) {
        guard let url = (sender?.representedObject as? URL) ?? selectedURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    @objc func toggleHidden(_ sender: Any?) {
        model.showsHiddenAndIgnored.toggle()
    }

    // MARK: Drag and drop (move within the folder)

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        (item as? FolderNode)?.url as NSURL?
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard info.draggingSource as? NSOutlineView === outlineView else { return [] }
        let folder = (item as? FolderNode).map { $0.entry.isDirectory ? $0.url : $0.url.deletingLastPathComponent() } ?? model.root
        let sources = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        // Not into itself or its own children, and not where it already is.
        guard !sources.isEmpty, !sources.contains(where: { folder.path == $0.path || folder.path.hasPrefix($0.path + "/") || $0.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL }) else { return [] }
        outlineView.setDropItem((item as? FolderNode).flatMap { $0.entry.isDirectory ? $0 : nil }, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let folder = (item as? FolderNode)?.url ?? model.root
        let sources = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        for source in sources { FolderFileOperations.move(source, into: folder, model: model) }
        return !sources.isEmpty
    }
}

extension Notification.Name {
    static let folderExpansionDidChange = Notification.Name("QuickEditFolderExpansionDidChange")
}
