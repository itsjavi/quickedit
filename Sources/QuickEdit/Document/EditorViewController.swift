import AppKit
import SwiftUI

/// A document window's content: the scrollable editor with its line-number ruler, and the status bar.
final class EditorViewController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate {
    let document: TextDocument
    private(set) var textView: EditorTextView!
    private(set) var scrollView: NSScrollView!
    private var layoutManager: EditorLayoutManager!
    private var ruler: LineNumberRulerView?
    let lineIndex = LineIndex()
    private var settings: AppSettings { .shared }
    private var state: EditorState { document.state }

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

        let root = NSView()
        root.addSubview(scrollView)
        root.addSubview(statusBar)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: StatusBarView.height),
        ])
        view = root

        storage.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange), name: .editorSettingsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewDidResize), name: NSView.frameDidChangeNotification, object: scrollView)
        applySettings()
        documentDidLoad()
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

    /// Called after the document's text was (re)loaded from disk.
    func documentDidLoad() {
        guard textView != nil else { return }
        lineIndex.invalidate()
        applySettings()
        updatePosition()
        updateRiskyCount()
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

    private func presentAlert(_ message: String, _ information: String) {
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
