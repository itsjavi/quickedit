import AppKit
import QuickEditCore
import UniformTypeIdentifiers

/// One text file. The document owns the text storage; its window's editor lays it out.
@objc(TextDocument)
final class TextDocument: NSDocument {
    let textStorage = NSTextStorage()
    let state = EditorState()
    /// The window's editor, once made.
    weak var editor: EditorViewController?

    override init() {
        super.init()
        let settings = AppSettings.shared
        state.indentation = settings.defaultIndentation
    }

    nonisolated override class var autosavesInPlace: Bool { AppSettings.autosavesInPlaceThisLaunch }

    /// Save As, Rename and Move can change the language and preview (e.g. Untitled → notes.md).
    nonisolated override var fileURL: URL? {
        didSet {
            guard oldValue?.lastPathComponent != fileURL?.lastPathComponent else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if self.editor?.isViewLoaded == true { self.editor?.updateLanguage() }
                }
            }
        }
    }

    // MARK: Reading

    /// The file being read (NSDocument sets `fileURL` only after reading), for `.editorconfig` lookup.
    private var readingURL: URL?

    nonisolated override func read(from url: URL, ofType typeName: String) throws {
        let number = Self.fileNumber(of: url)
        MainActor.assumeIsolated {
            readingURL = url
            presentedFileNumber = number
        }
        defer { MainActor.assumeIsolated { readingURL = nil } }
        try super.read(from: url, ofType: typeName)
    }

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        // Binary property lists are shown as XML, read-only until the user converts them (decision-3).
        if PropertyListText.isBinaryPropertyList(data) {
            guard let xml = try? PropertyListText.xmlText(fromBinary: data) else {
                throw Self.readError("This property list is damaged.", "QuickEdit couldn't read it as a binary property list.")
            }
            MainActor.assumeIsolated { load(DecodedText(text: xml, encoding: .utf8, isExact: true), binaryPropertyList: true) }
            return
        }
        let decoded: DecodedText
        do {
            decoded = try TextCodec.decode(data)
        } catch TextCodecError.binary {
            throw Self.readError("This file isn't text.", "QuickEdit opens text and source files.")
        } catch {
            throw Self.readError("QuickEdit can't tell this file's text encoding.", "Try opening it in another app.")
        }
        // Documents aren't read concurrently, so this runs on the main thread.
        MainActor.assumeIsolated { load(decoded, binaryPropertyList: false) }
    }

    private nonisolated static func readError(_ description: String, _ suggestion: String) -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadCorruptFile.rawValue, userInfo: [
            NSLocalizedDescriptionKey: description,
            NSLocalizedRecoverySuggestionErrorKey: suggestion,
        ])
    }

    private func load(_ decoded: DecodedText, binaryPropertyList: Bool) {
        let settings = AppSettings.shared
        state.encoding = decoded.encoding
        state.isBinaryPropertyList = binaryPropertyList
        if binaryPropertyList {
            state.readOnlyReason = "A binary property list, shown as XML. Convert it to XML to edit it; saving then writes XML."
        } else {
            state.readOnlyReason = decoded.isExact ? nil : "This file's text encoding couldn't be read exactly, so editing is off to avoid damaging it."
        }
        let endings = LineEndings.detect(decoded.text)
        let hasLineBreaks = !endings.counts.isEmpty
        let config = settings.useEditorConfig ? (readingURL ?? fileURL).map { EditorConfig.properties(for: $0) } ?? EditorConfigProperties() : EditorConfigProperties()
        state.editorConfig = config
        // Existing line endings are kept as they are; .editorconfig only decides for files without any.
        state.lineEnding = hasLineBreaks ? endings.dominant : config.endOfLine ?? .lf
        state.hasMixedLineEndings = endings.isMixed
        if let style = config.indentStyle {
            let width = config.indentSize ?? config.tabWidth ?? settings.tabWidth
            state.indentation = Indentation(style: style, width: max(1, width))
            state.indentationSource = .editorConfig
        } else if settings.detectIndentation, let detected = IndentationDetector.detect(decoded.text, tabWidth: config.tabWidth ?? settings.tabWidth) {
            state.indentation = detected
            state.indentationSource = .detected
        } else {
            state.indentation = Indentation(style: settings.indentWithTabs ? .tabs : .spaces, width: config.indentSize ?? settings.tabWidth)
            state.indentationSource = config.indentSize != nil ? .editorConfig : .settings
        }
        let selection = editor?.textView.selectedRange()
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: decoded.text)
        textStorage.endEditing()
        editor?.documentDidLoad(keeping: selection)
    }

    /// Makes a binary property list editable; the next save writes it as an XML property list.
    @objc func convertPropertyListToXML(_ sender: Any?) {
        guard state.isBinaryPropertyList else { return }
        state.isBinaryPropertyList = false
        state.readOnlyReason = nil
        updateChangeCount(.changeDone)
        editor?.applySettings()
    }

    // MARK: Saving

    /// Trimming and final newlines apply to saves the user asks for, never to autosaves while typing.
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        if saveOperation == .saveOperation || saveOperation == .saveAsOperation {
            editor?.applySaveTransforms(
                trimTrailingWhitespace: state.editorConfig.trimTrailingWhitespace ?? AppSettings.shared.trimTrailingWhitespace,
                insertFinalNewline: state.editorConfig.insertFinalNewline ?? AppSettings.shared.insertFinalNewline)
        }
        // Typing after a save must be a new undo step: otherwise NSTextView keeps coalescing it into the saved
        // one, the change count never moves, and the document doesn't know it has unsaved changes.
        editor?.textView.breakUndoCoalescing()
        let isNewName = saveOperation == .saveAsOperation
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            // An untitled file saved as notes.csv now has a language, a preview or a table.
            if error == nil, isNewName { self?.editor?.updateLanguage() }
            // What's on disk is this window's text again (a deleted file is back, a changed one overwritten).
            if error == nil, saveOperation != .autosaveElsewhereOperation {
                self?.setDiskChange(nil)
                self?.followFileAtPath()
            }
            completionHandler(error)
        }
    }

    // MARK: Changes on disk

    nonisolated override func presentedItemDidChange() {
        super.presentedItemDidChange()
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.checkForChangesOnDisk() }
        }
    }

    /// Compares the file on disk with the version this window last read or saved (decision-3). Without unsaved
    /// edits a change reloads at once; with them nothing is replaced and the bar above the editor lets the user
    /// choose. Runs on file-presenter notices and whenever the window becomes key, which also catches changes whose
    /// notice never came. Never shows a dialog: another app (or an agent) may be rewriting the file repeatedly.
    func checkForChangesOnDisk() {
        guard let url = fileURL, let known = fileModificationDate else { return }
        guard let modified = Self.diskModificationDate(of: url) else {
            if !FileManager.default.fileExists(atPath: url.path) { setDiskChange(.deleted) }
            return
        }
        // Any other date, not just a later one: `cp -p`, `git stash` and backups bring back older versions.
        followFileAtPath()
        guard modified != known else {
            if state.diskChange == .deleted { setDiskChange(nil) }
            return
        }
        // Touched, or rewritten with the same bytes: nothing to reload, and reloading would clear Undo.
        if diskHolds(textOf: url) {
            fileModificationDate = modified
            setDiskChange(nil)
            return
        }
        if isDocumentEdited {
            setDiskChange(.modified)
        } else {
            reloadFromDisk(presentingErrors: false)
        }
    }

    /// Reads the file again, keeping the caret and scroll position. Undo puts back the text that was showing, so
    /// neither an automatic reload nor the bar's Reload can lose edits.
    func reloadFromDisk(presentingErrors: Bool = true) {
        guard let url = fileURL, let type = fileType else { return }
        let previous = textStorage.string
        let read = { try self.revert(toContentsOf: url, ofType: type) }
        do {
            if let editor { try editor.keepingViewport(read) } else { try read() }
        } catch {
            // It may not be text anymore: keep what's showing and say the file changed.
            setDiskChange(FileManager.default.fileExists(atPath: url.path) ? .modified : .deleted)
            if presentingErrors, let window = windowForSheet {
                presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
            }
            return
        }
        setDiskChange(nil)
        // Older undo steps refer to the replaced text.
        undoManager?.removeAllActions()
        guard previous != textStorage.string, let undoManager, undoManager.groupingLevel == 0 else { return }
        // Its own top-level group, so the reload is one Undo step. Registering it counts as a change; clearing the
        // count afterwards keeps the reloaded text clean, and Undo makes the document edited again.
        let groupsByEvent = undoManager.groupsByEvent
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        let reloaded = textStorage.string
        undoManager.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated { document.swapReloadedText(previous, back: reloaded) }
        }
        undoManager.setActionName("Reload from Disk")
        undoManager.endUndoGrouping()
        undoManager.groupsByEvent = groupsByEvent
        updateChangeCount(.changeCleared)
    }

    /// Undo and Redo of a reload: puts `text` in place of the whole text and registers the way back. It edits the
    /// storage directly, because the text view's own undo record, made while undoing, keeps the old length and
    /// redoes only part of the text.
    private func swapReloadedText(_ text: String, back other: String) {
        editor?.textView.breakUndoCoalescing()
        let replace = { self.textStorage.replaceCharacters(in: NSRange(location: 0, length: self.textStorage.length), with: text) }
        if let editor { editor.keepingViewport(replace) } else { replace() }
        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated { document.swapReloadedText(other, back: text) }
        }
        undoManager?.setActionName("Reload from Disk")
    }

    /// Save also writes a file that was deleted on disk when there's nothing unsaved, which NSDocument skips.
    override func save(_ sender: Any?) {
        guard state.diskChange == .deleted, !isDocumentEdited, let url = fileURL, let type = fileType else {
            return super.save(sender)
        }
        save(to: url, ofType: type, for: .saveOperation) { [weak self] error in
            guard let self, let error, let window = windowForSheet else { return }
            presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
        }
    }

    /// Keeps the unsaved edits over the changed file: the next save overwrites it without asking again.
    func keepEditsOverDiskChange() {
        if let url = fileURL, let modified = Self.diskModificationDate(of: url) { fileModificationDate = modified }
        setDiskChange(nil)
    }

    /// The file (inode) the presenter follows. One that was deleted keeps the presenter attached and deaf to the
    /// file now at its path, which is how git and many tools replace files.
    private var presentedFileNumber: Int?

    /// Re-attaches the presenter when the file at the path is another one than it follows.
    private func followFileAtPath() {
        guard let url = fileURL, let number = Self.fileNumber(of: url), number != presentedFileNumber else { return }
        if presentedFileNumber != nil {
            NSFileCoordinator.removeFilePresenter(self)
            NSFileCoordinator.addFilePresenter(self)
        }
        presentedFileNumber = number
    }

    private func setDiskChange(_ change: DiskChange?) {
        guard state.diskChange != change else { return }
        state.diskChange = change
        editor?.diskChangeDidChange()
    }

    /// The file holds exactly what saving this window would write.
    private func diskHolds(textOf url: URL) -> Bool {
        guard let type = fileType, let disk = try? Data(contentsOf: url, options: .mappedIfSafe),
              let mine = try? data(ofType: type) else { return false }
        return disk == mine
    }

    /// Read fresh each time: URL resource values can be cached.
    private nonisolated static func diskModificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private nonisolated static func fileNumber(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? Int
    }

    // MARK: Writing

    override func data(ofType typeName: String) throws -> Data {
        if let reason = state.readOnlyReason {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "QuickEdit won't save this file.",
                NSLocalizedRecoverySuggestionErrorKey: reason,
            ])
        }
        do {
            return try TextCodec.encode(textStorage.string, as: state.encoding)
        } catch {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteInapplicableStringEncoding.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "The text can't be saved as \(state.encoding.displayName).",
                NSLocalizedRecoverySuggestionErrorKey: "Some characters don't exist in this encoding. Choose UTF-8 in the status bar's encoding menu, then save again.",
            ])
        }
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        // Source files keep whatever extension the user types (.ts, .env, Makefile…).
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        return true
    }

    // MARK: Errors

    override func presentError(_ error: Error, modalFor window: NSWindow, delegate: Any?, didPresent didPresentSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        guard Dialogs.shouldPresent(error) else { return }
        super.presentError(error, modalFor: window, delegate: delegate, didPresent: didPresentSelector, contextInfo: contextInfo)
    }

    override func presentError(_ error: Error) -> Bool {
        guard Dialogs.shouldPresent(error) else { return false }
        return super.presentError(error)
    }

    // MARK: Unsaved-changes indicator

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        refreshTabTitles()
    }

    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        refreshTabTitles()
    }

    /// Edits, undo, saves and reverts all end up in a change-count update; the tab's dot follows on the next turn.
    private func refreshTabTitles() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.windowControllers.forEach { ($0 as? DocumentWindowController)?.updateTabTitle() }
            }
        }
    }

    // MARK: Windows

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    override func showWindows() {
        for controller in windowControllers {
            guard let window = controller.window else { continue }
            FolderOpener.joinTabGroup(window)
            FolderOpener.present(window)
            if let folder = (controller as? DocumentWindowController)?.folder {
                FolderOpener.documentWindowAppeared(in: folder)
                if let url = fileURL { (controller as? DocumentWindowController)?.sidebar?.reveal(url, select: true) }
            }
        }
    }
}
