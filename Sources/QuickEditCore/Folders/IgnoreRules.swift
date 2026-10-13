import Foundation
import Synchronization

/// Every `.gitignore` that applies under an opened folder, evaluated like git: `.gitignore` files from the repository
/// top down to the path's folder (deeper files win, the last matching rule in a file wins), then
/// `.git/info/exclude`. A path inside an ignored folder is ignored whatever later rules say, and `.git` is always
/// ignored. When the folder sits inside a git repository, `.gitignore` files above it apply too and
/// `core.ignorecase` is honored; outside a repository its own `.gitignore` files still apply.
///
/// `.gitignore` files are read lazily and cached; call `reload()` after one changes.
public final class IgnoreRules: Sendable {
    public let root: URL
    /// The repository top level, or `root` when it isn't inside one. Rule paths are relative to it.
    let topPath: String
    let resolvedTopPath: String
    /// `root` relative to `topPath` ("" when they're the same folder).
    let rootRelative: String
    let ignoreCase: Bool
    let excludes: GitIgnore?
    private let cache = Mutex<[String: GitIgnore?]>([:])

    public init(root: URL) {
        let rootPath = Self.normalized(root.standardizedFileURL.path)
        self.root = URL(fileURLWithPath: rootPath, isDirectory: true)
        var top = rootPath
        var gitDir: String?
        var candidate = rootPath
        while true {
            if let found = Self.gitDirectory(in: candidate) {
                top = candidate
                gitDir = found
                break
            }
            if candidate == "/" { break }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        topPath = top
        resolvedTopPath = Self.normalized(URL(fileURLWithPath: top).resolvingSymlinksInPath().path)
        rootRelative = top == rootPath ? "" : String(rootPath.dropFirst(top == "/" ? 1 : top.count + 1))

        var ignoreCase = false
        var excludes: GitIgnore?
        if let gitDir {
            if let config = try? String(contentsOfFile: gitDir + "/config", encoding: .utf8) {
                ignoreCase = Self.configIgnoresCase(config)
            }
            if let text = Self.read(gitDir + "/info/exclude") {
                excludes = GitIgnore(contents: text, base: "", ignoreCase: ignoreCase)
            }
        }
        self.ignoreCase = ignoreCase
        self.excludes = excludes
    }

    /// Whether `url` (inside `root`) is ignored, by its own rules or because a folder above it (below `root`) is.
    /// `root` itself never is, so opening an ignored folder still shows its contents.
    public func isIgnored(_ url: URL, isDirectory: Bool) -> Bool {
        guard let path = relativeToTop(url), let belowRoot = pathBelowRoot(path), !belowRoot.isEmpty else { return false }
        let components = belowRoot.split(separator: "/")
        if components.contains(".git") { return true }
        var folder = rootRelative
        for component in components.dropLast() {
            let child = folder.isEmpty ? String(component) : folder + "/" + component
            if evaluate(child, isDirectory: true, chain: chain(forFolder: folder)) { return true }
            folder = child
        }
        return evaluate(path, isDirectory: isDirectory, chain: chain(forFolder: folder))
    }

    /// Forgets the cached `.gitignore` files.
    public func reload() {
        cache.withLock { $0.removeAll() }
    }

    // MARK: - Internals shared with FolderListing and FolderIndex

    /// The `.gitignore` in `folder` (relative to the top), read once. `exists: false` records that there is none
    /// without touching the disk.
    func gitIgnore(inFolder folder: String, exists: Bool? = nil) -> GitIgnore? {
        if let cached = cache.withLock({ $0[folder] }) { return cached }
        var loaded: GitIgnore?
        if exists != false, let text = Self.read(absolutePath(folder) + "/.gitignore") {
            let parsed = GitIgnore(contents: text, base: folder, ignoreCase: ignoreCase)
            if !parsed.isEmpty { loaded = parsed }
        }
        cache.withLock { $0[folder] = .some(loaded) }
        return loaded
    }

    /// The `.gitignore` files that apply to entries of `folder`, nearest first.
    func chain(forFolder folder: String) -> [GitIgnore] {
        var chain: [GitIgnore] = []
        var current = folder
        while true {
            if let ignore = gitIgnore(inFolder: current) { chain.append(ignore) }
            if current.isEmpty { break }
            current = current.lastIndex(of: "/").map { String(current[..<$0]) } ?? ""
        }
        return chain
    }

    /// Whether `path` (relative to the top) is ignored by its own rules, given the `.gitignore` chain of its folder.
    func evaluate(_ path: String, isDirectory: Bool, chain: [GitIgnore]) -> Bool {
        var path = path
        return path.withUTF8 { bytes in
            for ignore in chain {
                if let ignored = ignore.isIgnored(pathBytes: bytes, isDirectory: isDirectory) { return ignored }
            }
            return excludes?.isIgnored(pathBytes: bytes, isDirectory: isDirectory) ?? false
        }
    }

    /// `path` relative to the top, for a URL inside it.
    func relativeToTop(_ url: URL) -> String? {
        let path = Self.normalized(url.standardizedFileURL.path)
        if let relative = Self.relative(path, to: topPath) { return relative }
        let resolved = Self.normalized(url.resolvingSymlinksInPath().path)
        return Self.relative(resolved, to: resolvedTopPath)
    }

    /// The part of a top-relative path below `root`, or nil when the path isn't inside `root`.
    func pathBelowRoot(_ path: String) -> String? {
        if rootRelative.isEmpty { return path }
        if path == rootRelative { return "" }
        guard path.hasPrefix(rootRelative + "/") else { return nil }
        return String(path.dropFirst(rootRelative.count + 1))
    }

    func absolutePath(_ relative: String) -> String {
        if relative.isEmpty { return topPath }
        return topPath == "/" ? "/" + relative : topPath + "/" + relative
    }

    // MARK: - Helpers

    static func normalized(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    static func relative(_ path: String, to base: String) -> String? {
        if path == base { return "" }
        let prefix = base == "/" ? "/" : base + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
    }

    static func read(_ path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The git directory for a working tree folder: `.git` itself, or the `gitdir:` a `.git` file points to (linked
    /// worktrees and submodules), following `commondir` to the shared one.
    static func gitDirectory(in folder: String) -> String? {
        let dotGit = (folder == "/" ? "" : folder) + "/.git"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory) else { return nil }
        var gitDir = dotGit
        if !isDirectory.boolValue {
            guard let text = read(dotGit), let line = text.split(whereSeparator: \.isNewline).first,
                  line.hasPrefix("gitdir:")
            else { return nil }
            let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            gitDir = target.hasPrefix("/") ? target : (folder as NSString).appendingPathComponent(target)
        }
        if let common = read(gitDir + "/commondir")?.trimmingCharacters(in: .whitespacesAndNewlines), !common.isEmpty {
            gitDir = common.hasPrefix("/") ? common : (gitDir as NSString).appendingPathComponent(common)
        }
        return (gitDir as NSString).standardizingPath
    }

    /// `core.ignorecase` from a git config file.
    static func configIgnoresCase(_ config: String) -> Bool {
        var section = ""
        var ignoreCase = false
        for rawLine in config.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                section = line.dropFirst().prefix { $0 != "]" && $0 != " " && $0 != "\"" }.lowercased()
                continue
            }
            guard section == "core", let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces).lowercased()
            if key == "ignorecase" { ignoreCase = ["true", "yes", "on", "1"].contains(value) }
        }
        return ignoreCase
    }
}
