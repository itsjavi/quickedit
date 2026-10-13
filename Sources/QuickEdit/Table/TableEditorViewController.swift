import AppKit
import QuickEditCore

/// Spreadsheet-like editing of CSV/TSV files (TASK-17). The grid is a view of the text: every change is a minimal
/// text edit applied through the editor's text view, so only the edited cells' bytes change, quoting, delimiter and
/// line endings stay as they are, and undo is the document's.
final class TableEditorViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private unowned let editor: EditorViewController
    private let tableView = NSTableView()
    private var table = DelimitedText(delimiter: ",", rows: [])
    private var delimiter: Character = ","
    /// The first row names the columns instead of being a data row.
    private(set) var firstRowIsHeader = true
    private var headerToggle: NSButton!
    private var isApplyingEdit = false

    init(editor: EditorViewController) {
        self.editor = editor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private var isEditable: Bool { !editor.state.isReadOnly }
    /// Index of the first data row in `table.rows`.
    private var firstDataRow: Int { firstRowIsHeader && !table.rows.isEmpty ? 1 : 0 }

    override func loadView() {
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.gridStyleMask = [.solidVerticalGridLineMask]
        tableView.style = .plain
        tableView.rowHeight = 22
        tableView.dataSource = self
        tableView.delegate = self
        tableView.menu = contextMenu()

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        headerToggle = NSButton(checkboxWithTitle: "First row is header", target: self, action: #selector(toggleHeader(_:)))
        headerToggle.state = firstRowIsHeader ? .on : .off
        let buttons = NSStackView(views: [
            button("plus", "Add Row", #selector(addRow(_:))),
            button("minus", "Delete Selected Rows", #selector(deleteSelectedRows(_:))),
            button("rectangle.split.3x1", "Add Column", #selector(addColumn(_:))),
            button("rectangle.badge.minus", "Delete Column", #selector(deleteSelectedColumn(_:))),
            headerToggle,
        ])
        buttons.spacing = 10
        buttons.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(scrollView)
        root.addSubview(buttons)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttons.topAnchor),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        reload()
    }

    private func button(_ symbol: String, _ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .accessoryBarAction
        button.toolTip = title
        return button
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Insert Row Above", action: #selector(insertRowAbove(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Insert Row Below", action: #selector(addRow(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Delete Rows", action: #selector(deleteSelectedRows(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Insert Column Left", action: #selector(insertColumnLeft(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Insert Column Right", action: #selector(insertColumnRight(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Delete Column", action: #selector(deleteClickedColumn(_:)), keyEquivalent: "").target = self
        return menu
    }

    // MARK: Model

    /// Re-reads the grid from the editor's text (after edits, undo, reloads from disk).
    func reload() {
        guard isViewLoaded else { return }
        let text = editor.textView.string as NSString
        let ext = editor.document.fileURL?.pathExtension
        delimiter = editor.state.languageName == "TSV" ? "\t" : DelimitedText.detectDelimiter(text, fileExtension: ext)
        table = DelimitedText.parse(text, delimiter: delimiter)
        rebuildColumns()
        tableView.reloadData()
        for button in view.subviews.compactMap({ $0 as? NSStackView }).flatMap(\.views).compactMap({ $0 as? NSButton }) where button !== headerToggle {
            button.isEnabled = isEditable
        }
    }

    var rowCount: Int { max(0, table.rows.count - firstDataRow) }
    var columnCount: Int { max(1, table.columnCount) }

    private static let rowNumberColumn = NSUserInterfaceItemIdentifier("row")

    private func rebuildColumns() {
        let wanted = columnCount
        let dataColumns = tableView.tableColumns.filter { $0.identifier != Self.rowNumberColumn }
        if tableView.tableColumns.first?.identifier != Self.rowNumberColumn {
            let number = NSTableColumn(identifier: Self.rowNumberColumn)
            number.title = ""
            number.width = 44
            number.isEditable = false
            tableView.addTableColumn(number)
        }
        for column in dataColumns.dropFirst(wanted) { tableView.removeTableColumn(column) }
        for index in dataColumns.count..<max(wanted, dataColumns.count) {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(index)"))
            column.width = 140
            column.minWidth = 40
            tableView.addTableColumn(column)
        }
        for (index, column) in tableView.tableColumns.filter({ $0.identifier != Self.rowNumberColumn }).enumerated() {
            let title = firstRowIsHeader && !table.rows.isEmpty ? table.value(row: 0, column: index) : Self.letters(index)
            column.title = title.isEmpty ? Self.letters(index) : title
            column.headerToolTip = "Column \(Self.letters(index))"
        }
    }

    /// A, B, …, Z, AA, AB, … like a spreadsheet.
    static func letters(_ index: Int) -> String {
        var index = index
        var result = ""
        repeat {
            result = String(UnicodeScalar(UInt8(65 + index % 26))) + result
            index = index / 26 - 1
        } while index >= 0
        return result
    }

    private func dataColumnIndex(_ column: NSTableColumn?) -> Int? {
        guard let column, column.identifier != Self.rowNumberColumn else { return nil }
        return tableView.tableColumns.filter { $0.identifier != Self.rowNumberColumn }.firstIndex { $0 === column }
    }

    // MARK: Data source

    func numberOfRows(in tableView: NSTableView) -> Int { rowCount }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let isNumber = tableColumn?.identifier == Self.rowNumberColumn
        let identifier = NSUserInterfaceItemIdentifier(isNumber ? "numberCell" : "valueCell")
        let field = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField ?? {
            let field = NSTextField()
            field.identifier = identifier
            field.isBordered = false
            field.drawsBackground = false
            field.lineBreakMode = .byTruncatingTail
            field.cell?.usesSingleLineMode = true
            field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
            if isNumber {
                field.isEditable = false
                field.alignment = .right
                field.textColor = .tertiaryLabelColor
            } else {
                field.delegate = self
            }
            return field
        }()
        if isNumber {
            field.stringValue = String(row + firstDataRow + 1)
        } else if let column = dataColumnIndex(tableColumn) {
            let value = table.value(row: row + firstDataRow, column: column)
            // Line breaks inside a cell show as ⏎ in the grid; editing replaces the whole value.
            field.stringValue = value.replacingOccurrences(of: "\r\n", with: "⏎").replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "\r", with: "⏎")
            field.isEditable = isEditable && !value.contains(where: \.isNewline)
            field.toolTip = value.contains(where: \.isNewline) ? "This cell has line breaks; edit it in Text mode" : nil
        }
        return field
    }

    // MARK: Editing

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let row = tableView.row(for: field)
        let columnIndex = tableView.column(for: field)
        guard row >= 0, columnIndex >= 0, let column = dataColumnIndex(tableView.tableColumns[columnIndex]) else { return }
        let sourceRow = row + firstDataRow
        guard field.stringValue != table.value(row: sourceRow, column: column) else { return }
        apply([table.editCell(row: sourceRow, column: column, value: field.stringValue, lineEnding: editor.state.lineEnding)], actionName: "Edit Cell")
    }

    /// Applies edits (sorted from the end of the text to the start) as one undo step, then re-reads the grid.
    func apply(_ edits: [TextEdit], actionName: String) {
        let edits = edits.filter { !$0.isEmpty }
        guard isEditable, !edits.isEmpty else { return }
        let undoManager = editor.textView.undoManager
        undoManager?.beginUndoGrouping()
        isApplyingEdit = true
        for edit in edits { editor.textView.replace(edit.range, with: edit.replacement) }
        isApplyingEdit = false
        undoManager?.setActionName(actionName)
        undoManager?.endUndoGrouping()
        let selection = tableView.selectedRowIndexes
        reload()
        tableView.selectRowIndexes(selection.filteredIndexSet { $0 < rowCount }, byExtendingSelection: false)
    }

    private var isReloadScheduled = false

    /// Called for every character edit of the text (synchronously): re-read the grid after undo, redo, reloads
    /// from disk or typing in Text mode, but not after the grid's own edits (it already did, and a late reload
    /// would end the cell editing that Tab just started).
    func textDidChange() {
        guard !isApplyingEdit, !isReloadScheduled else { return }
        isReloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.isReloadScheduled = false
                self?.reload()
            }
        }
    }

    @objc func toggleHeader(_ sender: Any?) {
        firstRowIsHeader.toggle()
        headerToggle.state = firstRowIsHeader ? .on : .off
        reload()
    }

    @objc func addRow(_ sender: Any?) {
        let after = tableView.selectedRowIndexes.last.map { $0 + firstDataRow + 1 } ?? table.rows.count
        apply([table.insertRow(at: after, lineEnding: editor.state.lineEnding)], actionName: "Add Row")
        tableView.selectRowIndexes([after - firstDataRow], byExtendingSelection: false)
        tableView.scrollRowToVisible(after - firstDataRow)
    }

    @objc func insertRowAbove(_ sender: Any?) {
        let target = clickedOrSelectedRows().first.map { $0 + firstDataRow } ?? firstDataRow
        apply([table.insertRow(at: target, lineEnding: editor.state.lineEnding)], actionName: "Add Row")
    }

    @objc func deleteSelectedRows(_ sender: Any?) {
        let rows = IndexSet(clickedOrSelectedRows().map { $0 + firstDataRow })
        guard !rows.isEmpty else { return }
        apply(table.deleteRows(rows), actionName: rows.count == 1 ? "Delete Row" : "Delete Rows")
    }

    @objc func addColumn(_ sender: Any?) {
        apply(table.insertColumn(at: table.columnCount), actionName: "Add Column")
    }

    @objc func insertColumnLeft(_ sender: Any?) {
        guard let column = clickedColumn() else { return }
        apply(table.insertColumn(at: column), actionName: "Add Column")
    }

    @objc func insertColumnRight(_ sender: Any?) {
        guard let column = clickedColumn() else { return }
        apply(table.insertColumn(at: column + 1), actionName: "Add Column")
    }

    @objc func deleteClickedColumn(_ sender: Any?) {
        guard let column = clickedColumn() else { return }
        apply(table.deleteColumn(column), actionName: "Delete Column")
    }

    /// Deletes the column of the cell being edited or the last clicked one, else the last column.
    @objc func deleteSelectedColumn(_ sender: Any?) {
        let column = clickedColumn() ?? (tableView.selectedColumn >= 0 ? dataColumnIndex(tableView.tableColumns[tableView.selectedColumn]) : nil)
            ?? table.columnCount - 1
        guard column >= 0, table.columnCount > 0 else { return }
        apply(table.deleteColumn(column), actionName: "Delete Column")
    }

    private func clickedOrSelectedRows() -> IndexSet {
        let clicked = tableView.clickedRow
        if clicked >= 0, !tableView.selectedRowIndexes.contains(clicked) { return [clicked] }
        return tableView.selectedRowIndexes
    }

    private func clickedColumn() -> Int? {
        let clicked = tableView.clickedColumn
        guard clicked >= 0 else { return nil }
        return dataColumnIndex(tableView.tableColumns[clicked])
    }

    // MARK: Test hooks

    /// Edits a cell as the grid would (Test builds); `row` counts data rows.
    func setCell(row: Int, column: Int, value: String) {
        apply([table.editCell(row: row + firstDataRow, column: column, value: value, lineEnding: editor.state.lineEnding)], actionName: "Edit Cell")
    }

    func selectRows(_ rows: IndexSet) {
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
    }
}
