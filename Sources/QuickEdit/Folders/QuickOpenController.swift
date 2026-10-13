import AppKit
import QuickEditCore

/// ⌘P: find a file of the folder by name (fuzzy) and open it as a tab. A sheet on the folder window.
final class QuickOpenController: NSViewController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let model: FolderModel
    private let field = NSSearchField()
    private let table = NSTableView()
    private var paths: [String] = []
    private(set) var results: [FuzzyMatcher.Match] = []
    static let limit = 60

    init(model: FolderModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Shows Quick Open for the folder of the key window (or the frontmost folder).
    static func show(in window: NSWindow?) {
        guard let window, let model = folder(of: window) else { return }
        let controller = QuickOpenController(model: model)
        if AppVariant.isBackground { current = controller; _ = controller.view; controller.loadIndex(); return }
        window.contentViewController?.presentAsSheet(controller)
    }

    /// The Test build keeps the controller here instead of showing a sheet.
    nonisolated(unsafe) static var current: QuickOpenController?

    static func folder(of window: NSWindow) -> FolderModel? {
        FolderRegistry.folders.first { $0.tabbingIdentifier == window.tabbingIdentifier }
    }

    override func loadView() {
        field.placeholderString = "Open a file in “\(model.name)”"
        field.delegate = self
        field.sendsSearchStringImmediately = true
        field.translatesAutoresizingMaskIntoConstraints = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 34
        table.style = .inset
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 420))
        root.addSubview(field)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            field.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: 560),
            root.heightAnchor.constraint(equalToConstant: 420),
        ])
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(field)
        loadIndex()
    }

    func loadIndex() {
        model.withFileIndex { [weak self] paths in
            self?.paths = paths
            self?.search(self?.field.stringValue ?? "")
        }
    }

    /// Ranks the folder's files for `query` (also the Test-build hook's path).
    func search(_ query: String) {
        field.stringValue = query
        results = FuzzyMatcher.match(query, in: paths, limit: Self.limit)
        table.reloadData()
        if !results.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    func controlTextDidChange(_ obj: Notification) {
        search(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            table.selectRowIndexes([min(table.selectedRow + 1, results.count - 1)], byExtendingSelection: false)
            table.scrollRowToVisible(table.selectedRow)
        case #selector(NSResponder.moveUp(_:)):
            table.selectRowIndexes([max(table.selectedRow - 1, 0)], byExtendingSelection: false)
            table.scrollRowToVisible(table.selectedRow)
        case #selector(NSResponder.insertNewline(_:)):
            openSelected()
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss(nil)
        default:
            return false
        }
        return true
    }

    @objc func openSelected() {
        let row = max(table.selectedRow, 0)
        guard row < results.count else { return }
        let url = model.root.appendingPathComponent(results[row].path)
        if presentingViewController != nil { dismiss(nil) }
        FolderOpener.open(url, in: model)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let result = results[row]
        let name = (result.path as NSString).lastPathComponent
        let folder = (result.path as NSString).deletingLastPathComponent
        let title = NSMutableAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        // Bold the matched characters that fall in the file name.
        let nameStart = (result.path as NSString).length - (name as NSString).length
        for index in result.matches where index >= nameStart {
            title.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: NSRange(location: index - nameStart, length: 1))
        }
        let text = NSTextField(labelWithAttributedString: title)
        let subtitle = NSTextField(labelWithString: folder.isEmpty ? "/" : folder)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        let icon = NSImageView(image: FileIcons.file(model.root.appendingPathComponent(result.path), appearance: tableView.effectiveAppearance))
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let labels = NSStackView(views: [text, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 0
        let row = NSStackView(views: [icon, labels])
        row.spacing = 8
        return row
    }
}
