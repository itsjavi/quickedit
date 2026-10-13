import AppKit
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

    // MARK: Reading

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        let decoded: DecodedText
        do {
            decoded = try TextCodec.decode(data)
        } catch TextCodecError.binary {
            throw Self.readError("This file isn't text.", "QuickEdit opens text and source files.")
        } catch {
            throw Self.readError("QuickEdit can't tell this file's text encoding.", "Try opening it in another app.")
        }
        // Documents aren't read concurrently, so this runs on the main thread.
        MainActor.assumeIsolated { load(decoded) }
    }

    private nonisolated static func readError(_ description: String, _ suggestion: String) -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadCorruptFile.rawValue, userInfo: [
            NSLocalizedDescriptionKey: description,
            NSLocalizedRecoverySuggestionErrorKey: suggestion,
        ])
    }

    private func load(_ decoded: DecodedText) {
        state.encoding = decoded.encoding
        state.readOnlyReason = decoded.isExact ? nil : "This file's text encoding couldn't be read exactly, so editing is off to avoid damaging it."
        let endings = LineEndings.detect(decoded.text)
        state.lineEnding = endings.dominant
        state.hasMixedLineEndings = endings.isMixed
        if AppSettings.shared.detectIndentation, let detected = IndentationDetector.detect(decoded.text) {
            state.indentation = detected
            state.indentationSource = .detected
        } else {
            state.indentation = AppSettings.shared.defaultIndentation
            state.indentationSource = .settings
        }
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: decoded.text)
        textStorage.endEditing()
        editor?.documentDidLoad()
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
