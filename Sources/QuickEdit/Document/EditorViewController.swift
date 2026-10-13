import AppKit
import QuickEditCore
import SwiftUI

/// A document window's content: the scrollable editor with its line-number ruler, and the status bar.
final class EditorViewController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate, NSMenuItemValidation {
    let document: TextDocument
    private(set) var textView: EditorTextView!
    private(set) var scrollView: NSScrollView!
    private var layoutManager: EditorLayoutManager!
    private var ruler: LineNumberRulerView?
    private var splitView: NSSplitView!
    private var previewHost: NSView?
    let preview = PreviewModel()
    let lineIndex = LineIndex()
    private var settings: AppSettings { .shared }
    var state: EditorState { document.state }

    init(document: TextDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
        document.editor = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let storage = document.textStorage
        layoutManager = EditorLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 6
        layoutManager.addTextContainer(container)

        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.displaysLinkToolTips = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.delegate = self
        self.textView = textView

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView = scrollView

        let statusBar = NSHostingView(rootView: StatusBarView(state: state, controller: self))
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        splitView.addArrangedSubview(scrollView)
        self.splitView = splitView

        let root = NSView()
        root.addSubview(splitView)
        root.addSubview(statusBar)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: root.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: StatusBarView.height),
        ])
        view = root

        storage.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange), name: .editorSettingsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewDidResize), name: NSView.frameDidChangeNotification, object: scrollView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(editorDidScroll), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        applySettings()
        documentDidLoad()
    }

    // MARK: Preview

    /// Sets up the preview for Markdown and HTML files (after loading, saving under a new name, or a language change).
    func updatePreviewKind() {
        let name = document.fileURL?.lastPathComponent ?? document.displayName ?? ""
        let kind = PreviewKind.forFile(named: name)
        let changed = kind != state.previewKind
        state.previewKind = kind
        if let kind {
            preview.kind = kind
            preview.directory = document.fileURL?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
            preview.onOpenFile = { url in
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
            if changed { state.mode = settings.editorMode }
            preview.onTranscribe = kind == .markdown ? { [weak self] source in self?.beginTranscription(source: source) } : nil
        } else {
            state.mode = .edit
        }
        applyMode()
    }

    func setMode(_ mode: EditorMode) {
        guard state.previewKind != nil else { return }
        state.mode = mode
        settings.editorMode = mode
        applyMode()
    }

    func setAllowsRemoteContent(_ allows: Bool) {
        state.allowsRemoteContent = allows
        preview.allowsRemoteContent = allows
    }

    private func applyMode() {
        let mode = state.previewKind == nil ? EditorMode.edit : state.mode
        if mode != .edit, previewHost == nil {
            let host = NSHostingView(rootView: DocumentPreview(model: preview))
            host.translatesAutoresizingMaskIntoConstraints = true
            splitView.addArrangedSubview(host)
            previewHost = host
        }
        if mode != .edit { preview.text = textView.string }
        scrollView.isHidden = mode == .preview
        previewHost?.isHidden = mode == .edit
        splitView.adjustSubviews()
        if mode == .split, splitView.subviews.count == 2 {
            splitView.setPosition(splitView.bounds.width / 2, ofDividerAt: 0)
        }
        if mode == .preview, let window = view.window, window.firstResponder === textView {
            window.makeFirstResponder(nil)
        }
    }

    private var isPreviewVisible: Bool { state.previewKind != nil && state.mode != .edit }

    @objc private func editorDidScroll() {
        guard isPreviewVisible, state.mode == .split, state.previewKind == .markdown,
              let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let visible = textView.visibleRect
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: visible.minY - textView.textContainerOrigin.y), in: container)
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        let line = lineIndex.line(of: character, in: textView.string as NSString) + 1
        if preview.scrollLine != line { preview.scrollLine = line }
    }

    @objc func showEditorOnly(_ sender: Any?) { setMode(.edit) }
    @objc func showSplit(_ sender: Any?) { setMode(.split) }
    @objc func showPreviewOnly(_ sender: Any?) { setMode(.preview) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let modes: [Selector: EditorMode] = [#selector(showEditorOnly(_:)): .edit, #selector(showSplit(_:)): .split, #selector(showPreviewOnly(_:)): .preview]
        if menuItem.action == #selector(recordVoiceNote(_:)) {
            menuItem.title = state.voiceRecorder.isRecording ? "Show Voice Recorder" : "Record Voice Note"
            return canRecordVoiceNote
        }
        if let action = menuItem.action, let mode = modes[action] {
            menuItem.state = state.previewKind != nil && state.mode == mode ? .on : .off
            return state.previewKind != nil
        }
        return true
    }

    func tearDown() {
        NotificationCenter.default.removeObserver(self)
        document.textStorage.delegate = nil
        document.textStorage.removeLayoutManager(layoutManager)
    }

    // MARK: Configuration

    @objc private func settingsDidChange() {
        applySettings()
    }

    /// Applies app settings and the document's indentation and line ending to the editor.
    func applySettings() {
        guard let textView else { return }
        textView.indentation = state.indentation
        textView.lineEnding = state.lineEnding
        textView.isEditable = !state.isReadOnly
        textView.highlightsCurrentLine = settings.highlightCurrentLine
        layoutManager.showsInvisibles = settings.showInvisibles
        applyWrap(settings.wrapLines)
        applyLineNumbers(settings.showLineNumbers)
        applyBaseAttributes()
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        let font = settings.editorFont
        let paragraph = NSMutableParagraphStyle()
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        paragraph.tabStops = []
        paragraph.defaultTabInterval = spaceWidth * CGFloat(max(1, state.indentation.width))
        paragraph.lineHeightMultiple = 1.1
        return [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
    }

    /// The whole text uses one font and tab width; syntax colours are layout-manager temporary attributes.
    private func applyBaseAttributes() {
        let attributes = baseAttributes
        let storage = document.textStorage
        textView.typingAttributes = attributes
        textView.font = attributes[.font] as? NSFont
        storage.beginEditing()
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        ruler?.textDidChange()
    }

    private func applyWrap(_ wrap: Bool) {
        guard let container = textView.textContainer else { return }
        let contentSize = scrollView.contentSize
        if wrap {
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            container.widthTracksTextView = true
            textView.setFrameSize(NSSize(width: contentSize.width, height: textView.frame.height))
        } else {
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            container.widthTracksTextView = false
            container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        }
        textView.minSize = NSSize(width: wrap ? 0 : contentSize.width, height: contentSize.height)
        textView.sizeToFit()
    }

    @objc private func scrollViewDidResize() {
        guard !settings.wrapLines else { return }
        // Without wrapping, the text view is at least as wide as the visible area (background, current line).
        textView.minSize = NSSize(width: scrollView.contentSize.width, height: scrollView.contentSize.height)
        textView.sizeToFit()
    }

    private func applyLineNumbers(_ show: Bool) {
        if show {
            if ruler == nil {
                ruler = LineNumberRulerView(textView: textView, scrollView: scrollView, lineIndex: lineIndex)
                scrollView.verticalRulerView = ruler
            }
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
        } else {
            scrollView.rulersVisible = false
        }
    }

    // MARK: Document events

    /// Called after the document's text was (re)loaded from disk; keeps the caret near `selection`.
    func documentDidLoad(keeping selection: NSRange? = nil) {
        guard textView != nil else { return }
        lineIndex.invalidate()
        applySettings()
        if let selection {
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
        updatePosition()
        updateRiskyCount()
        updatePreviewKind()
    }

    // MARK: Text events

    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            lineIndex.invalidate()
            // Not during the storage's edit processing: the ruler may widen, which changes layout.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.ruler?.textDidChange()
                    self.updatePosition()
                    self.updateRiskyCount()
                    if self.isPreviewVisible { self.preview.text = self.textView.string }
                }
            }
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updatePosition()
        ruler?.needsDisplay = true
    }

    private func updatePosition() {
        guard let textView else { return }
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let line = lineIndex.line(of: selection.location, in: text)
        let lineStart = lineIndex.start(ofLine: line, in: text)
        state.line = line + 1
        state.column = text.substring(with: NSRange(location: lineStart, length: selection.location - lineStart)).count + 1
        state.selectionLength = selection.length
        state.lineCount = lineIndex.lineCount(in: text)
    }

    private func updateRiskyCount() {
        state.riskyCount = RiskyCharacters.count(in: document.textStorage.string as NSString)
    }

    // MARK: Commands

    /// Moves the caret to a 1-based line (and column) and scrolls it into view.
    func goToLine(_ line: Int, column: Int = 1) {
        let text = textView.string as NSString
        let start = lineIndex.start(ofLine: line - 1, in: text)
        let lineRange = text.lineRange(for: NSRange(location: start, length: 0))
        var contentsEnd = 0
        text.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
        let location = min(start + max(column - 1, 0), max(start, min(contentsEnd, NSMaxRange(lineRange))))
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(NSRange(location: location, length: 0))
    }

    @objc func showGoToLine(_ sender: Any?) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.informativeText = "Enter a line number, optionally followed by :column."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "\(state.line)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let parts = field.stringValue.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard let line = parts.first else { return }
            self?.goToLine(line, column: parts.count > 1 ? parts[1] : 1)
        }
    }

    /// Sets the indentation used by Tab, indent commands and tab stops for this file.
    func setIndentation(_ indentation: Indentation) {
        state.indentation = indentation
        state.indentationSource = .manual
        applySettings()
    }

    /// Rewrites leading whitespace to `target` as one undoable change and uses it from now on.
    func convertIndentation(to target: Indentation) {
        let old = textView.string
        let converted = IndentationDetector.convert(old, from: state.indentation, to: target)
        replaceAllText(with: converted, actionName: "Convert Indentation")
        setIndentation(target)
    }

    func detectIndentation() {
        if let detected = IndentationDetector.detect(textView.string) {
            state.indentation = detected
            state.indentationSource = .detected
        } else {
            state.indentation = settings.defaultIndentation
            state.indentationSource = .settings
        }
        applySettings()
    }

    /// Converts every line ending to `ending` as one undoable change; new lines use it from now on.
    func convertLineEndings(to ending: LineEnding) {
        let converted = LineEndings.convert(textView.string, to: ending)
        replaceAllText(with: converted, actionName: "Convert Line Endings")
        state.lineEnding = ending
        state.hasMixedLineEndings = false
        applySettings()
    }

    /// The encoding the next save writes; refuses ones that can't hold the current text.
    func setSaveEncoding(_ encoding: TextEncoding) {
        if (try? TextCodec.encode(textView.string, as: encoding)) == nil {
            presentAlert("The text can't be saved as \(encoding.displayName).", "Some characters don't exist in that encoding.")
            return
        }
        guard encoding != state.encoding else { return }
        state.encoding = encoding
        document.updateChangeCount(.changeDone)
    }

    /// Reads the file from disk again, decoding it as `encoding`.
    func reopen(with encoding: TextEncoding) {
        guard let url = document.fileURL else { return }
        if document.isDocumentEdited {
            presentAlert("Save or revert your changes first.", "Reopening with another encoding reads the file from disk again.")
            return
        }
        do {
            let decoded = try TextCodec.decode(Data(contentsOf: url), as: encoding)
            document.textStorage.replaceCharacters(in: NSRange(location: 0, length: document.textStorage.length), with: decoded.text)
            state.encoding = decoded.encoding
            state.readOnlyReason = decoded.isExact ? nil : "The file can't be read exactly as \(encoding.displayName), so editing is off to avoid damaging it."
            document.undoManager?.removeAllActions()
            documentDidLoad()
        } catch {
            presentAlert("The file can't be read as \(encoding.displayName).", "Choose another encoding.")
        }
    }

    /// Replaces the whole text as one undoable change, keeping the caret and scroll position close.
    private func replaceAllText(with text: String, actionName: String) {
        guard text != textView.string else { return }
        let selection = textView.selectedRange()
        let visible = scrollView.contentView.bounds.origin
        textView.replace(NSRange(location: 0, length: (textView.string as NSString).length), with: text)
        textView.undoManager?.setActionName(actionName)
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        scrollView.contentView.scroll(to: visible)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func presentAlert(_ message: String, _ information: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = information
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else if !AppVariant.isBackground {
            alert.runModal()
        }
    }
}
