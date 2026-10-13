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
        MainActor.assumeIsolated { readingURL = url }
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
        super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
    }

    // MARK: Changes on disk

    nonisolated override func presentedItemDidChange() {
        super.presentedItemDidChange()
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.fileDidChangeOnDisk() }
        }
    }

    /// Another app changed the file: reload when there are no unsaved edits, otherwise let the user choose.
    private func fileDidChangeOnDisk() {
        guard let url = fileURL, let type = fileType, let known = fileModificationDate,
              let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              modified > known, !isAskingAboutDiskChange
        else { return }
        guard isDocumentEdited else {
            try? revert(toContentsOf: url, ofType: type)
            return
        }
        let window = windowControllers.first?.window
        isAskingAboutDiskChange = true
        let alert = NSAlert()
        alert.messageText = "“\(displayName ?? "This file")” changed on disk."
        alert.informativeText = "Another app changed the file while you have unsaved edits here."
        alert.addButton(withTitle: "Keep My Edits")
        alert.addButton(withTitle: "Reload from Disk")
        Dialogs.show(alert, for: window) { [weak self] response in
            guard let self else { return }
            isAskingAboutDiskChange = false
            if response == .alertSecondButtonReturn {
                try? revert(toContentsOf: url, ofType: type)
            } else {
                // The user chose their version: the next save overwrites the disk one without asking again.
                fileModificationDate = modified
            }
        }
    }

    private var isAskingAboutDiskChange = false

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

    // MARK: Windows

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    override func showWindows() {
        guard AppVariant.isBackground else {
            super.showWindows()
            return
        }
        // The agents' Test build never activates or brings windows forward.
        NSApp.unhideWithoutActivation()
        for controller in windowControllers {
            guard let window = controller.window else { continue }
            if let host = NSApp.windows.first(where: { $0 !== window && $0.isVisible && $0.tabbingIdentifier == window.tabbingIdentifier }) {
                host.addTabbedWindow(window, ordered: .above)
            }
            window.orderBack(nil)
        }
    }
}

