import AppKit

/// New, rename, move and trash in a folder's tree. Moves and renames are coordinated, so open documents follow
/// their files (NSDocument is a file presenter). Nothing is ever deleted permanently.
enum FolderFileOperations {
    /// Asks for a name and creates an empty file (opened as a tab) or a folder in `folder`.
    static func newItem(in folder: URL, isFolder: Bool, model: FolderModel, window: NSWindow?) {
        askName(title: isFolder ? "New Folder" : "New File", initial: isFolder ? "untitled folder" : "untitled.txt", window: window) { name in
            create(named: name, in: folder, isFolder: isFolder, model: model)
        }
    }

    /// Creates the item (also the Test-build hook's path); returns its URL.
    @discardableResult
    static func create(named name: String, in folder: URL, isFolder: Bool, model: FolderModel) -> URL? {
        guard let url = validTarget(name, in: folder) else { return nil }
        do {
            if isFolder {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            } else {
                guard FileManager.default.createFile(atPath: url.path, contents: Data()) else { throw CocoaError(.fileWriteUnknown) }
            }
        } catch {
            report(error)
            return nil
        }
        model.expanded.insert(folder.standardizedFileURL)
        model.refresh(folder)
        if !isFolder { FolderOpener.open(url, in: model) }
        return url
    }

    static func rename(_ url: URL, model: FolderModel, window: NSWindow?) {
        askName(title: "Rename “\(url.lastPathComponent)”", initial: url.lastPathComponent, window: window) { name in
            rename(url, to: name, model: model)
        }
    }

    @discardableResult
    static func rename(_ url: URL, to name: String, model: FolderModel) -> URL? {
        guard name != url.lastPathComponent, let target = validTarget(name, in: url.deletingLastPathComponent()) else { return nil }
        return coordinatedMove(url, to: target, model: model)
    }

    @discardableResult
    static func move(_ url: URL, into folder: URL, model: FolderModel) -> URL? {
        guard let target = validTarget(url.lastPathComponent, in: folder) else { return nil }
        return coordinatedMove(url, to: target, model: model)
    }

    static func trash(_ url: URL, model: FolderModel) {
        var trashError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: nil) { actual in
            do { try FileManager.default.trashItem(at: actual, resultingItemURL: nil) } catch { trashError = error }
        }
        if let trashError { report(trashError) }
        model.refresh(url.deletingLastPathComponent())
    }

    // MARK: Helpers

    private static func coordinatedMove(_ source: URL, to target: URL, model: FolderModel) -> URL? {
        var moveError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: source, options: .forMoving, writingItemAt: target, options: .forReplacing, error: nil) { from, to in
            do {
                coordinator.item(at: from, willMoveTo: to)
                try FileManager.default.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            } catch {
                moveError = error
            }
        }
        if let moveError {
            report(moveError)
            return nil
        }
        model.refresh(source.deletingLastPathComponent())
        model.refresh(target.deletingLastPathComponent())
        return target
    }

    /// `name` in `folder`, refusing paths, empty names and existing items.
    private static func validTarget(_ name: String, in folder: URL) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != ".", trimmed != ".." else {
            report(message: "“\(name)” isn't a valid name.")
            return nil
        }
        let url = folder.appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            report(message: "“\(trimmed)” already exists in “\(folder.lastPathComponent)”.")
            return nil
        }
        return url
    }

    private static func askName(title: String, initial: String, window: NSWindow?, then create: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        Dialogs.show(alert, for: window) { response in
            if response == .alertFirstButtonReturn { create(field.stringValue) }
        }
        // Select the name without its extension, like Finder.
        let base = (initial as NSString).deletingPathExtension
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (base as NSString).length)
    }

    private static func report(_ error: Error) {
        report(message: error.localizedDescription)
    }

    private static func report(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        Dialogs.show(alert, for: NSApp.keyWindow)
    }
}
