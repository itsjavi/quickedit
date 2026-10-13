import AppKit
import Observation
import QuickEditCore

extension Notification.Name {
    /// Posted by a `FolderModel` when its tree changed on disk or its filters changed; sidebars reload.
    static let folderModelDidChange = Notification.Name("QuickEditFolderModelDidChange")
}

/// One open folder (decision-6): its tree, ignore rules, the sidebar state every window of the folder shares, and
/// the file index Quick Open searches. The windows of a folder form one native tab group.
@Observable final class FolderModel {
    let root: URL
    /// Show dotfiles and `.gitignore`d paths in the tree (they're always dimmed).
    var showsHiddenAndIgnored = false {
        didSet { if showsHiddenAndIgnored != oldValue { invalidateAll() } }
    }
    /// Expanded folders, shared by the sidebars of every window in the group.
    var expanded: Set<URL> = []

    @ObservationIgnored private var listings: [URL: [FolderEntry]] = [:]
    @ObservationIgnored let rules: IgnoreRules
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var index: [String]?
    @ObservationIgnored private var indexWaiters: [([String]) -> Void] = []
    @ObservationIgnored private var isIndexing = false

    var name: String { FileManager.default.displayName(atPath: root.path) }
    /// Windows of this folder share this identifier, so AppKit keeps them in one tab group.
    var tabbingIdentifier: String { "QuickEditFolder:" + root.path }

    init(root: URL) {
        self.root = root.standardizedFileURL.canonical
        rules = IgnoreRules(root: self.root)
        expanded = [self.root]
        watcher = FileWatcher(url: self.root) { [weak self] paths in self?.filesChanged(paths) }
    }

    func close() {
        watcher?.stop()
        watcher = nil
    }

    func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.canonical.path
        return path == root.path || path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
    }

    func relativePath(of url: URL) -> String {
        let path = url.standardizedFileURL.canonical.path
        return path == root.path ? "" : String(path.dropFirst(root.path.count + 1))
    }

    // MARK: Tree

    /// The children shown under `folder`, folders first; hidden and ignored ones only when they're shown.
    func children(of folder: URL) -> [FolderEntry] {
        let key = folder.standardizedFileURL
        if listings[key] == nil {
            listings[key] = (try? FolderListing.children(of: key, rules: rules)) ?? []
        }
        // .git is never worth showing, even with hidden and ignored files on.
        let all = (listings[key] ?? []).filter { !($0.isDirectory && $0.name == ".git") }
        return showsHiddenAndIgnored ? all : all.filter { !$0.isHidden && !$0.isIgnored }
    }

    private func invalidateAll() {
        listings.removeAll()
        index = nil
        NotificationCenter.default.post(name: .folderModelDidChange, object: self)
    }

    /// FSEvents: re-lists the loaded folders the events touch and tells the sidebars which ones changed. Events in
    /// folders nobody has expanded (a build folder churning, say) and edits that leave a listing as it was cost
    /// almost nothing and reload no sidebar; a changed `.gitignore` re-reads every rule.
    private func filesChanged(_ paths: [String]) {
        var touched: Set<URL> = []
        var indexIsStale = false
        if paths.contains(where: { ($0 as NSString).lastPathComponent == ".gitignore" || $0.contains("/.git/info/exclude") }) {
            rules.reload()
            touched = Set(listings.keys)
            indexIsStale = true
        } else {
            for path in paths {
                let url = listingKey(forEventPath: path)
                for folder in [url.deletingLastPathComponent(), url] where listings[folder] != nil {
                    touched.insert(folder)
                }
                if !indexIsStale, index != nil, isIndexed(url) { indexIsStale = true }
            }
        }
        if indexIsStale { index = nil }
        var changed: Set<URL> = []
        for folder in touched {
            let entries = try? FolderListing.children(of: folder, rules: rules)
            if entries != listings[folder] { changed.insert(folder) }
            listings[folder] = entries
        }
        guard !changed.isEmpty else { return }
        NotificationCenter.default.post(name: .folderModelDidChange, object: self, userInfo: [Self.changedFoldersKey: changed])
    }

    /// An FSEvents path (a real path, `/private/tmp/…`) in the form listings are keyed by (`standardizedFileURL`,
    /// which drops `/private` only for paths that exist), also for items that are gone.
    private func listingKey(forEventPath path: String) -> URL {
        let parent = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent, isDirectory: true).standardizedFileURL
        return parent.appendingPathComponent((path as NSString).lastPathComponent)
    }

    /// Whether Quick Open's index lists `url` (or would list files under it).
    private func isIndexed(_ url: URL) -> Bool {
        guard contains(url) else { return false }
        if showsHiddenAndIgnored { return true }
        if relativePath(of: url).split(separator: "/").contains(where: { $0.hasPrefix(".") }) { return false }
        return !rules.isIgnored(url, isDirectory: false)
    }

    /// The folders whose listing changed, in a `folderModelDidChange` notification's user info. Without it,
    /// everything may have changed.
    static let changedFoldersKey = "changedFolders"

    /// Re-lists `folder` now (after a file operation, before FSEvents reports it).
    func refresh(_ folder: URL) {
        let key = folder.standardizedFileURL
        listings[key] = nil
        index = nil
        NotificationCenter.default.post(name: .folderModelDidChange, object: self, userInfo: [Self.changedFoldersKey: Set([key])])
    }

    // MARK: Quick Open

    /// Relative paths of every file Quick Open can find, built off the main thread and cached until the tree changes.
    func withFileIndex(_ completion: @escaping ([String]) -> Void) {
        if let index {
            completion(index)
            return
        }
        indexWaiters.append(completion)
        guard !isIndexing else { return }
        isIndexing = true
        let indexer = FolderIndex(root: root, includeHidden: showsHiddenAndIgnored, includeIgnored: showsHiddenAndIgnored, rules: rules)
        Task.detached(priority: .userInitiated) {
            let paths = (try? indexer.build()) ?? []
            await MainActor.run { [weak self] in
                guard let self else { return }
                isIndexing = false
                index = paths
                let waiters = indexWaiters
                indexWaiters = []
                for waiter in waiters { waiter(paths) }
            }
        }
    }
}

/// The open folders, so files opened from anywhere inside one join its window group.
enum FolderRegistry {
    private(set) static var folders: [FolderModel] = []
    private static let openFoldersKey = "openFolders"

    /// The innermost open folder containing `url`.
    static func folder(containing url: URL?) -> FolderModel? {
        guard let url else { return nil }
        return folders.filter { $0.contains(url) }.max { $0.root.path.count < $1.root.path.count }
    }

    static func model(for root: URL) -> FolderModel {
        let canonical = root.standardizedFileURL.canonical
        if let existing = folders.first(where: { $0.root == canonical }) { return existing }
        let model = FolderModel(root: canonical)
        folders.append(model)
        remember()
        return model
    }

    static func close(_ model: FolderModel) {
        model.close()
        folders.removeAll { $0 === model }
        remember()
    }

    /// Windows (documents and the placeholder) showing `model`.
    static func windows(of model: FolderModel) -> [NSWindow] {
        NSApp.windows.filter { $0.tabbingIdentifier == model.tabbingIdentifier && ($0.isVisible || $0.isMiniaturized) }
    }

    private static func remember() {
        guard !AppVariant.isBackground else { return }
        UserDefaults.standard.set(folders.map(\.root.path), forKey: openFoldersKey)
    }

    /// Folders open when the app last quit (restored at launch).
    static var rememberedFolders: [URL] {
        (UserDefaults.standard.stringArray(forKey: openFoldersKey) ?? []).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
