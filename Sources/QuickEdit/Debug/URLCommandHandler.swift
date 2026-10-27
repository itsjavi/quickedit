import AVFoundation
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
        case "ui/discard":
            // Closes without saving or asking (Test builds; drops autosaved untitled drafts).
            guard let document = editor?.document else { return }
            document.updateChangeCount(.changeCleared)
            document.close()
        case "ui/close":
            editor?.view.window?.performClose(nil)
        case "ui/save":
            editor?.document.save(nil)
        case "ui/disk-change":
            // The bar's buttons, and the check a window runs when it becomes key (Test windows never do).
            switch query["action"] {
            case "check": editor?.document.checkForChangesOnDisk()
            case "reload": editor?.document.reloadFromDisk()
            case "keep": editor?.document.keepEditsOverDiskChange()
            default: break
            }
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
            guard let name = query["name"], let editor else { return }
            let action = Selector(name)
            // NSApp.sendAction reaches the document after the window chain; a background window isn't key, so walk it here.
            if !editor.textView.tryToPerform(action, with: nil), editor.document.responds(to: action) {
                editor.document.perform(action, with: nil)
            }
        case "ui/mode":
            if let mode = EditorMode(rawValue: query["value"] ?? "") { editor?.setMode(mode) }
        case "ui/remote-content":
            editor?.setAllowsRemoteContent(query["value"] == "1")
        case "ui/voice-start":
            // The recorder's real start/stop path, with the microphone replaced by a clip copied from
            // `from` or a generated tone of `seconds`.
            guard let editor else { return }
            let source = query["from"].flatMap { safePath($0) }.map { URL(fileURLWithPath: $0) }
            editor.document.state.voiceRecorder.simulatedClip = { url in makeClip(at: url, from: source, query: query) }
            editor.recordVoiceNote(nil)
        case "ui/voice-stop", "ui/voice-cancel":
            guard let recorder = editor?.document.state.voiceRecorder else { return }
            if verb == "ui/voice-stop" { recorder.stop() } else { recorder.cancel() }
        case "ui/close-sheet":
            editor?.document.state.transcribeSource = nil
            if let window = editor?.view.window, let sheet = window.attachedSheet { window.endSheet(sheet) }
        case "ui/transcript":
            // Inserts a transcript as the sheet's Insert would (no speech model needed).
            if let source = query["src"] { editor?.insertTranscript(query["text"] ?? "", forSource: source) }
        case "ui/table":
            editor?.setShowsTable(query["value"] != "0")
        case "ui/table-cell":
            guard let row = Int(query["row"] ?? ""), let column = Int(query["column"] ?? "") else { return }
            editor?.tableController?.setCell(row: row, column: column, value: query["value"] ?? "")
        case "ui/table-select":
            let rows = (query["rows"] ?? "").split(separator: ",").compactMap { Int($0) }
            editor?.tableController?.selectRows(IndexSet(rows))
        case "ui/table-command":
            // addRow:, insertRowAbove:, deleteSelectedRows:, addColumn:, deleteSelectedColumn:, toggleHeader:
            guard let name = query["name"], let table = editor?.tableController else { return }
            _ = table.perform(Selector(name), with: nil)
        case "ui/settings":
            SettingsNavigation.shared.tab = query["tab"] == "filetypes" ? .fileTypes : .general
            (NSApp.delegate as? AppDelegate)?.showSettings(nil)
        case "ui/file-types":
            // check=all|none|<uti,uti>; apply=1 runs Apply (a dry run in the Test build).
            let associations = SettingsNavigation.shared.associations
            associations.reload()
            switch query["check"] {
            case "all": associations.setAll(true)
            case "none": associations.setAll(false)
            case let ids?: for id in ids.split(separator: ",") { associations.setChecked(true, for: String(id)) }
            case nil: break
            }
            if query["apply"] == "1" { Task { await associations.apply() } }
        case "debug/file-types":
            guard let path = safePath(query["out"]) else { return }
            let associations = SettingsNavigation.shared.associations
            if associations.rows.isEmpty { associations.reload() }
            var lines = associations.rows.map { "\($0.language)\t\($0.id)\t.\($0.extensions.joined(separator: " ."))\t\($0.currentApp?.lastPathComponent ?? "-")\tchecked=\($0.isChecked)" }
            lines.append("dryRun: \(associations.dryRunChanges.joined(separator: "; "))")
            lines.append("result: \(associations.lastResult ?? "-")")
            try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        case "ui/fold-line":
            // Same path as clicking the gutter arrow on a 1-based line.
            if let line = Int(query["line"] ?? "") { editor?.toggleFold(atLine: line - 1) }
        case "ui/open-folder":
            if let path = safePath(query["path"]) { FolderOpener.openFolder(URL(fileURLWithPath: path)) }
        case "ui/tree-open":
            // A click on a file in the sidebar; `path` is relative to the folder (`folder=` picks it by suffix).
            guard let model = targetFolder(query["folder"]), let path = query["path"] else { return }
            FolderOpener.open(model.root.appendingPathComponent(path), in: model)
        case "ui/tree-expand":
            guard let model = targetFolder(query["folder"]) else { return }
            let url = model.root.appendingPathComponent(query["path"] ?? "").standardizedFileURL
            if query["value"] == "0" { model.expanded.remove(url) } else { model.expanded.insert(url) }
            NotificationCenter.default.post(name: .folderExpansionDidChange, object: model)
        case "ui/tree-op":
            // op=new-file|new-folder&path=<folder>&name= · op=rename&path=&name= · op=move&path=&to=<folder> · op=trash&path=
            guard let model = targetFolder(query["folder"]) else { return }
            let url = model.root.appendingPathComponent(query["path"] ?? "")
            switch query["op"] {
            case "new-file": FolderFileOperations.create(named: query["name"] ?? "", in: url, isFolder: false, model: model)
            case "new-folder": FolderFileOperations.create(named: query["name"] ?? "", in: url, isFolder: true, model: model)
            case "rename": FolderFileOperations.rename(url, to: query["name"] ?? "", model: model)
            case "move": FolderFileOperations.move(url, into: model.root.appendingPathComponent(query["to"] ?? ""), model: model)
            case "trash": FolderFileOperations.trash(url, model: model)
            default: break
            }
        case "ui/folder-hidden":
            targetFolder(query["folder"])?.showsHiddenAndIgnored = query["value"] == "1"
        case "ui/quick-open":
            // Opens Quick Open for the folder (kept off screen in the Test build), searches `q`, and with pick=N opens result N.
            guard let model = targetFolder(query["folder"]), let window = FolderRegistry.windows(of: model).first else { return }
            QuickOpenController.show(in: window)
            guard let controller = QuickOpenController.current else { return }
            let q = query["q"] ?? ""
            let pick = Int(query["pick"] ?? "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    controller.search(q)
                    if let pick, pick < controller.results.count {
                        FolderOpener.open(model.root.appendingPathComponent(controller.results[pick].path), in: model)
                    }
                }
            }
        case "debug/folders":
            guard let path = safePath(query["out"]) else { return }
            var lines: [String] = []
            for model in FolderRegistry.folders {
                lines.append("folder: \(model.root.path) hidden=\(model.showsHiddenAndIgnored)")
                let windows = FolderRegistry.windows(of: model)
                lines.append("  windows: \(windows.map(\.title)) tabs=\(windows.first?.tabbedWindows?.count ?? 1)")
                // The selected tab's sidebar: hidden tabs catch up with changes when shown.
                let shown = windows.sorted { a, _ in (a.tabGroup?.selectedWindow ?? a) === a }
                let sidebar = shown.compactMap { ($0.windowController as? DocumentWindowController)?.sidebar
                    ?? ($0.contentViewController as? FolderSplitViewController)?.sidebar }.first
                for row in sidebar?.visibleRows ?? [] { lines.append("  | " + row) }
            }
            if let controller = QuickOpenController.current {
                lines.append("quickOpen: \(controller.results.prefix(8).map(\.path))")
            }
            try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        case "ui/front":
            // Agreed UI sessions only: shows the window above others (no activation) so WebKit paints for captures.
            guard let window = editor?.view.window else { return }
            if query["value"] == "0" { window.orderBack(nil) } else { window.orderFrontRegardless() }
        case "debug/editor-bench":
            // Types `count` characters one by one into the middle of the open file (or at `location`), laying out
            // and recolouring the visible range after each, and writes per-keystroke timings. `pause=1` then waits
            // for the catch-up reparse after typing stops and adds its main-thread cost.
            guard let path = safePath(query["out"]), let editor else { return }
            let count = Int(query["count"] ?? "") ?? 200
            let textView = editor.textView!
            let middle = Int(query["location"] ?? "") ?? (textView.string as NSString).length / 2
            editor.colorizer.catchUpTimings.removeAll()
            textView.setSelectedRange(NSRange(location: middle, length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
            var phases: [[Double]] = [[], [], [], []]
            func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
            for index in 0..<count {
                let t0 = now()
                textView.insertText(index % 20 == 19 ? "\n" : "x", replacementRange: textView.selectedRange())
                let t1 = now()
                if let layoutManager = textView.layoutManager, let container = textView.textContainer {
                    layoutManager.ensureLayout(forBoundingRect: textView.visibleRect, in: container)
                }
                let t2 = now()
                editor.colorizer.colorVisibleRange()
                let t3 = now()
                textView.displayIfNeeded()
                let t4 = now()
                for (phase, (a, b)) in [(t0, t1), (t1, t2), (t2, t3), (t3, t4)].enumerated() { phases[phase].append(Double(b - a) / 1_000_000) }
            }
            let totals = (0..<count).map { i in phases.reduce(0) { $0 + $1[i] } }.sorted()
            func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
            let report = String(format: "keystrokes: %d\nmedian: %.2f ms\np95: %.2f ms\nmax: %.2f ms\ninsert+parse: %.2f\nlayout: %.2f\ncolor: %.2f\ndisplay: %.2f\nlength: %d\n", count,
                                totals[totals.count / 2], totals[Int(Double(totals.count) * 0.95)], totals.last ?? 0,
                                median(phases[0]), median(phases[1]), median(phases[2]), median(phases[3]), (textView.string as NSString).length)
            guard query["pause"] == "1" else {
                try? report.write(toFile: path, atomically: true, encoding: .utf8)
                return
            }
            let colorizer: SyntaxColorizer = editor.colorizer
            Task {
                let deadline = ContinuousClock.now + .seconds(20)
                while colorizer.isCatchingUp, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
                let timings = colorizer.catchUpTimings.map { Double($0.components.attoseconds) / 1e15 + Double($0.components.seconds) * 1000 }
                let catchUp = String(format: "catchup-steps: %d\ncatchup-main-max: %.2f ms\ncatchup-done: %@\n", timings.count,
                                     timings.max() ?? 0, colorizer.isCatchingUp ? "no" : "yes")
                try? (report + catchUp).write(toFile: path, atomically: true, encoding: .utf8)
            }
        case "debug/scroll-bench":
            // Scrolls from the top to the end in `step`-point jumps (a fast fling), drawing after each, and writes
            // per-step timings and how often the newly visible text had no layout yet.
            guard let path = safePath(query["out"]), let editor, let layoutManager = editor.textView.layoutManager,
                  let container = editor.textView.textContainer else { return }
            let step = CGFloat(Double(query["step"] ?? "") ?? 120)
            let textView = editor.textView!
            let clip = editor.scrollView.contentView
            clip.scroll(to: .zero)
            editor.scrollView.reflectScrolledClipView(clip)
            textView.displayIfNeeded()
            var phases: [[Double]] = [[], [], []]
            var unlaid = 0
            func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
            var y: CGFloat = 0
            while y + clip.bounds.height < textView.frame.height {
                y += step
                // Without forcing layout: does what's about to show already have it?
                let origin = textView.textContainerOrigin
                let rect = NSRect(x: 0, y: y - origin.y, width: clip.bounds.width, height: clip.bounds.height)
                let laid = layoutManager.glyphRange(forBoundingRectWithoutAdditionalLayout: rect, in: container)
                let covered = laid.length > 0 ? layoutManager.boundingRect(forGlyphRange: laid, in: container).maxY : 0
                if covered + 40 < min(rect.maxY, textView.frame.height - 2 * origin.y) { unlaid += 1 }
                let t0 = now()
                clip.scroll(to: NSPoint(x: 0, y: y))
                editor.scrollView.reflectScrolledClipView(clip)
                let t1 = now()
                editor.ruler?.displayIfNeeded()
                let t2 = now()
                textView.displayIfNeeded()
                let t3 = now()
                for (phase, (a, b)) in [(t0, t1), (t1, t2), (t2, t3)].enumerated() { phases[phase].append(Double(b - a) / 1_000_000) }
            }
            let steps = phases[0].count
            guard steps > 0 else { return }
            let totals = (0..<steps).map { i in phases.reduce(0) { $0 + $1[i] } }.sorted()
            func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
            let report = String(format: "steps: %d\nunlaid: %d\nmedian: %.2f ms\np95: %.2f ms\nmax: %.2f ms\nscroll: %.2f\nruler: %.2f\ntext: %.2f\nlength: %d\n", steps, unlaid,
                                totals[steps / 2], totals[Int(Double(steps) * 0.95)], totals.last ?? 0,
                                median(phases[0]), median(phases[1]), median(phases[2]), (textView.string as NSString).length)
            try? report.write(toFile: path, atomically: true, encoding: .utf8)
        case "ui/language":
            editor?.setLanguage(id: query["id"].flatMap { $0.isEmpty ? nil : $0 })
        case "debug/tokens":
            // Token kinds of a range, one "text<TAB>kind" per token.
            guard let path = safePath(query["out"]), let editor else { return }
            let text = editor.textView.string as NSString
            let location = min(Int(query["location"] ?? "") ?? 0, text.length)
            let range = NSRange(location: location, length: min(Int(query["length"] ?? "") ?? text.length, text.length - location))
            let lines = editor.colorizer.tokens(in: range).map { "\(text.substring(with: $0.range).debugDescription)\t\($0.kind)" }
            try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
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
        case "status-bar": settings.showStatusBar = on
        case "font-size": if let size = Double(query["value"] ?? "") { settings.fontSize = size }
        case "file-icons": if let style = FileIconStyle(rawValue: query["value"] ?? "") { settings.fileIcons = style }
        default: break
        }
    }

    /// Copies `source` to `url`, or writes a short 440 Hz tone (`seconds`, default 1).
    private static func makeClip(at url: URL, from source: URL?, query: [String: String]) -> Bool {
        if let source { return (try? FileManager.default.copyItem(at: source, to: url)) != nil }
        let seconds = Double(query["seconds"] ?? "") ?? 1
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * 44_100)),
              let samples = buffer.floatChannelData?[0]
        else { return false }
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) { samples[index] = 0.3 * sin(2 * .pi * 440 * Float(index) / 44_100) }
        do {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1]
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
            return true
        } catch {
            return false
        }
    }

    private static func targetFolder(_ suffix: String?) -> FolderModel? {
        if let suffix, !suffix.isEmpty { return FolderRegistry.folders.first { $0.root.path.hasSuffix(suffix) } }
        return FolderRegistry.folders.last
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
        lines.append("suppressedDialog: \(Dialogs.lastSuppressed ?? "-")")
        lines.append("windows: \(NSApp.windows.filter(\.isVisible).map(\.title))")
        lines.append("tabGroups: \(Set(NSApp.windows.compactMap { $0.tabbedWindows?.count }).sorted())")
        for (index, editor) in editors.enumerated() {
            let state = editor.document.state
            let prefix = "doc\(index)"
            lines.append("\(prefix).path: \(editor.document.fileURL?.path ?? "untitled")")
            lines.append("\(prefix).window: \(editor.view.window.map { "\($0.frame) screen=\($0.screen?.visibleFrame ?? .zero)" } ?? "-")")
            lines.append("\(prefix).edited: \(editor.document.isDocumentEdited) tab=\(editor.view.window?.tab.attributedTitle?.string ?? editor.view.window?.title ?? "-")")
            lines.append("\(prefix).position: \(state.line):\(state.column) selected=\(state.selectionLength) lines=\(state.lineCount)")
            lines.append("\(prefix).language: \(state.languageName)")
            lines.append("\(prefix).indentation: \(state.indentation.style.rawValue) \(state.indentation.width) (\(state.indentationSource.rawValue))")
            lines.append("\(prefix).encoding: \(state.encoding.displayName)")
            lines.append("\(prefix).lineEnding: \(state.lineEnding.displayName)\(state.hasMixedLineEndings ? " mixed" : "")")
            lines.append("\(prefix).risky: \(state.riskyCount)")
            lines.append("\(prefix).readOnly: \(state.readOnlyReason ?? "no")")
            lines.append("\(prefix).diskChange: \(state.diskChange?.rawValue ?? "none") statusBar=\(AppSettings.shared.showStatusBar)")
            if let table = editor.tableController, state.showsTable {
                lines.append("\(prefix).table: rows=\(table.rowCount) columns=\(table.columnCount) header=\(table.firstRowIsHeader)")
            }
            lines.append("\(prefix).folds: regions=\(editor.foldableRegions.count) folded=\(editor.editorLayoutManager.foldedRanges.map { "\($0.location)+\($0.length)" }) markers=\(editor.foldMarkers().sorted { $0.key < $1.key }.map { "\($0.key + 1)\($0.value ? "▸" : "▾")" })")
            lines.append("\(prefix).voice: recording=\(state.voiceRecorder.isRecording) transcribe=\(state.transcribeSource ?? "-")")
            lines.append("\(prefix).preview: \(state.previewKind.map { "\($0)" } ?? "none") mode=\(state.mode.rawValue) remote=\(state.allowsRemoteContent)")
            lines.append("\(prefix).undo: \(editor.document.undoManager?.undoActionName ?? "")")
            let textView = editor.textView!
            lines.append("\(prefix).layout: frame=\(textView.frame) visible=\(textView.visibleRect) container=\(textView.textContainer?.size ?? .zero) laidOut=\(editor.editorLayoutManager.firstUnlaidCharacterIndex())/\(editor.document.textStorage.length)")
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
