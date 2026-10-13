import AppKit
import WebKit
import QuickEditCore

/// Handles the app's URL scheme. Release builds accept no verbs; DEBUG builds expose
/// test hooks that call the same methods as the UI, restricted to temp folders.
enum URLCommandHandler {
    static func handle(_ url: URL) {
        #if DEBUG
        DebugHooks.handle(url)
        #endif
    }
}

#if DEBUG
enum DebugHooks {
    static func handle(_ url: URL) {
        // Only the agents' Test build.
        guard url.scheme == AppVariant.urlScheme, AppVariant.name == "test" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let verb = (url.host() ?? "") + url.path()
        let editor = targetEditor(query["doc"])
        // Documents outside temp folders are never touched.
        if verb != "debug/state", verb != "ui/new", verb != "ui/open", verb != "ui/appearance",
           let path = editor?.document.fileURL?.path, safePath(path) == nil { return }

        switch verb {
        case "ui/open":
            if let path = safePath(query["path"]) {
                NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { _, _, _ in }
            }
        case "ui/new":
            guard let document = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as? TextDocument else { return }
            if let text = query["text"], let editor = document.editor { editor.textView.insertText(text, replacementRange: NSRange(location: 0, length: 0)) }
        case "ui/close":
            editor?.view.window?.performClose(nil)
        case "ui/save":
            editor?.document.save(nil)
        case "ui/window-size":
            guard let window = editor?.view.window, let width = Double(query["w"] ?? ""), let height = Double(query["h"] ?? "") else { return }
            window.setContentSize(NSSize(width: width, height: height))
        case "ui/appearance":
            if let mode = AppearanceMode(rawValue: query["value"] ?? "") { AppSettings.shared.appearance = mode }
        case "ui/setting":
            applySetting(query)
        case "ui/type":
            guard let textView = editor?.textView else { return }
            textView.insertText(query["text"] ?? "", replacementRange: textView.selectedRange())
        case "ui/select":
            guard let textView = editor?.textView else { return }
            let length = (textView.string as NSString).length
            let location = min(Int(query["location"] ?? "") ?? 0, length)
            textView.setSelectedRange(NSRange(location: location, length: min(Int(query["length"] ?? "") ?? 0, length - location)))
        case "ui/goto-line":
            editor?.goToLine(Int(query["line"] ?? "") ?? 1, column: Int(query["column"] ?? "") ?? 1)
        case "ui/command":
            // Same responder-chain path as the menu item, starting at the editor.
            guard let name = query["name"], let textView = editor?.textView else { return }
            _ = textView.tryToPerform(Selector(name), with: nil)
        case "ui/mode":
            if let mode = EditorMode(rawValue: query["value"] ?? "") { editor?.setMode(mode) }
        case "ui/remote-content":
            editor?.setAllowsRemoteContent(query["value"] == "1")
        case "ui/indentation":
            guard let editor else { return }
            let style: IndentStyle = query["style"] == "tabs" ? .tabs : .spaces
            let target = Indentation(style: style, width: Int(query["width"] ?? "") ?? editor.document.state.indentation.width)
            if query["convert"] == "1" { editor.convertIndentation(to: target) } else { editor.setIndentation(target) }
        case "ui/line-endings":
            if let ending = LineEnding.allCases.first(where: { $0.displayName.lowercased() == query["value"]?.lowercased() }) {
                editor?.convertLineEndings(to: ending)
            }
        case "debug/preview":
            // The preview page's text and the computed colour of its first heading and `.local` paragraph.
            guard let path = safePath(query["out"]), let root = editor?.view, let webView = findWebView(in: root) else { return }
            let script = """
            const h = document.querySelector('h1'); const l = document.querySelector('.local');
            return [document.body ? document.body.innerText : '(no body)',
                    'h1 color: ' + (h ? getComputedStyle(h).color : '-'),
                    '.local color: ' + (l ? getComputedStyle(l).color : '-'),
                    'url: ' + location.href].join('\\n');
            """
            Task {
                let result = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)
                try? ((result as? String) ?? "(no result)").write(toFile: path, atomically: true, encoding: .utf8)
            }
        case "debug/snapshot":
            // Renders the editor's text view in-process (independent of window-server capture).
            guard let path = safePath(query["out"]), let textView = editor?.textView,
                  let rep = textView.bitmapImageRepForCachingDisplay(in: textView.visibleRect) else { return }
            textView.cacheDisplay(in: textView.visibleRect, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        case "debug/state":
            if let path = safePath(query["out"]) { try? stateDump().write(toFile: path, atomically: true, encoding: .utf8) }
        default:
            break
        }
    }

    private static func applySetting(_ query: [String: String]) {
        let settings = AppSettings.shared
        let on = query["value"] == "1"
        switch query["name"] {
        case "line-numbers": settings.showLineNumbers = on
        case "invisibles": settings.showInvisibles = on
        case "wrap": settings.wrapLines = on
        case "current-line": settings.highlightCurrentLine = on
        case "font-size": if let size = Double(query["value"] ?? "") { settings.fontSize = size }
        default: break
        }
    }

    private static func findWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for subview in view.subviews { if let found = findWebView(in: subview) { return found } }
        return nil
    }

    private static var editors: [EditorViewController] {
        NSDocumentController.shared.documents.compactMap { ($0 as? TextDocument)?.editor }
    }

    /// The document whose path ends with `suffix`, else the frontmost document window's.
    private static func targetEditor(_ suffix: String?) -> EditorViewController? {
        if let suffix, !suffix.isEmpty {
            return editors.first { $0.document.fileURL?.path.hasSuffix(suffix) == true || $0.document.displayName == suffix }
        }
        let ordered = NSApp.orderedWindows.compactMap { window in editors.first { $0.view.window === window } }
        return ordered.first ?? editors.last
    }

    private static func safePath(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let absolute = URL(fileURLWithPath: raw.hasPrefix("/") ? raw : "/" + raw).standardizedFileURL
        // realpath, not resolvingSymlinksInPath (which turns /private/tmp into /tmp); the leaf may not exist yet.
        guard let parent = realpath(absolute.deletingLastPathComponent().path, nil) else { return nil }
        defer { free(parent) }
        let resolved = URL(fileURLWithPath: String(cString: parent)).appendingPathComponent(absolute.lastPathComponent).path
        let allowed = ["/private/tmp/", "/private/var/folders/"]
        return allowed.contains { resolved.hasPrefix($0) } ? resolved : nil
    }

    private static func stateDump() -> String {
        var lines: [String] = []
        lines.append("variant: \(AppVariant.name)")
        lines.append("appearance: \(AppSettings.shared.appearance.rawValue)")
        lines.append("windows: \(NSApp.windows.filter(\.isVisible).map(\.title))")
        lines.append("tabGroups: \(Set(NSApp.windows.compactMap { $0.tabbedWindows?.count }).sorted())")
        for (index, editor) in editors.enumerated() {
            let state = editor.document.state
            let prefix = "doc\(index)"
            lines.append("\(prefix).path: \(editor.document.fileURL?.path ?? "untitled")")
            lines.append("\(prefix).edited: \(editor.document.isDocumentEdited)")
            lines.append("\(prefix).position: \(state.line):\(state.column) selected=\(state.selectionLength) lines=\(state.lineCount)")
            lines.append("\(prefix).language: \(state.languageName)")
            lines.append("\(prefix).indentation: \(state.indentation.style.rawValue) \(state.indentation.width) (\(state.indentationSource.rawValue))")
            lines.append("\(prefix).encoding: \(state.encoding.displayName)")
            lines.append("\(prefix).lineEnding: \(state.lineEnding.displayName)\(state.hasMixedLineEndings ? " mixed" : "")")
            lines.append("\(prefix).risky: \(state.riskyCount)")
            lines.append("\(prefix).readOnly: \(state.readOnlyReason ?? "no")")
            lines.append("\(prefix).preview: \(state.previewKind.map { "\($0)" } ?? "none") mode=\(state.mode.rawValue) remote=\(state.allowsRemoteContent)")
            lines.append("\(prefix).undo: \(editor.document.undoManager?.undoActionName ?? "")")
            let textView = editor.textView!
            lines.append("\(prefix).layout: frame=\(textView.frame) visible=\(textView.visibleRect) container=\(textView.textContainer?.size ?? .zero)")
            if editor.document.textStorage.length > 0 {
                let attributes = editor.document.textStorage.attributes(at: 0, effectiveRange: nil)
                lines.append("\(prefix).attributes: font=\((attributes[.font] as? NSFont)?.fontName ?? "-") color=\(String(describing: attributes[.foregroundColor]))")
            }
            lines.append("\(prefix).text: \(textView.string.prefix(400).debugDescription)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
#endif
