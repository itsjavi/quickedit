import Foundation
import Synchronization

/// Every file under a folder, as relative paths for Quick Open. Skips `.git`, and unless asked, hidden items
/// (names starting with a dot) and `.gitignore`d ones, without descending into skipped folders. Symbolic links to
/// files are listed; links to folders aren't followed. Build it off the main thread; `cancel()` (or cancelling the
/// surrounding task) stops it.
public final class FolderIndex: Sendable {
    public static let defaultLimit = 200_000

    public let root: URL
    public let includeHidden: Bool
    public let includeIgnored: Bool
    /// The most paths `build()` returns; a result of exactly `limit` paths may be truncated.
    public let limit: Int
    private let rules: IgnoreRules?
    private let cancelled = Atomic<Bool>(false)

    /// `rules` lets the index share the tree's cached `.gitignore` files; one is created when needed and nil.
    public init(
        root: URL, includeHidden: Bool = false, includeIgnored: Bool = false, limit: Int = FolderIndex.defaultLimit,
        rules: IgnoreRules? = nil
    ) {
        self.root = root.standardizedFileURL
        self.includeHidden = includeHidden
        self.includeIgnored = includeIgnored
        self.limit = max(0, limit)
        self.rules = includeIgnored ? nil : (rules ?? IgnoreRules(root: root))
    }

    public func cancel() {
        cancelled.store(true, ordering: .relaxed)
    }

    /// Relative paths (`/`-separated) of the files under `root`, sorted. Throws `CancellationError` when cancelled.
    public func build() throws -> [String] {
        var results: [String] = []
        let rootPath = IgnoreRules.normalized(root.path)
        let rootRelative = rules?.rootRelative ?? ""
        // (absolute path, path relative to root, .gitignore chain of the folder's parent)
        var stack: [(absolute: String, relative: String, parentChain: [GitIgnore])] = [(rootPath, "", [])]
        var isRoot = true

        while let folder = stack.popLast() {
            if cancelled.load(ordering: .relaxed) || Task.isCancelled { throw CancellationError() }
            let entries = Self.readFolder(folder.absolute)

            var chain = folder.parentChain
            let topRelative = Self.join(rootRelative, folder.relative)
            if let rules {
                if isRoot {
                    chain = rules.chain(forFolder: topRelative)
                } else if let own = rules.gitIgnore(inFolder: topRelative, exists: entries.contains { $0.name == ".gitignore" }) {
                    chain.insert(own, at: 0)
                }
            }
            isRoot = false

            for entry in entries {
                if entry.name == ".git" { continue }
                if !includeHidden, entry.name.hasPrefix(".") { continue }
                let absolute = folder.absolute == "/" ? "/" + entry.name : folder.absolute + "/" + entry.name
                var kind = entry.kind
                if kind == .unknown || kind == .link { kind = Self.kind(of: absolute, followLinks: kind == .link) }
                let relative = Self.join(folder.relative, entry.name)
                if let rules {
                    let isDirectory = entry.kind == .directory || (entry.kind == .unknown && kind == .directory)
                    if rules.evaluate(Self.join(rootRelative, relative), isDirectory: isDirectory, chain: chain) { continue }
                }
                switch kind {
                case .directory where entry.kind != .link:
                    stack.append((absolute, relative, chain))
                case .file:
                    results.append(relative)
                    if results.count >= limit { return results.sorted() }
                default:
                    break
                }
            }
        }
        return results.sorted()
    }

    // MARK: - Reading folders

    enum Kind { case file, directory, link, other, unknown }

    static func join(_ folder: String, _ name: String) -> String {
        folder.isEmpty ? name : name.isEmpty ? folder : folder + "/" + name
    }

    /// Names and types from `readdir`, without a `stat` per entry (unreadable folders read as empty).
    static func readFolder(_ path: String) -> [(name: String, kind: Kind)] {
        guard let directory = opendir(path) else { return [] }
        defer { closedir(directory) }
        var entries: [(name: String, kind: Kind)] = []
        while let entry = readdir(directory) {
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafeBytes(of: &entry.pointee.d_name) { raw in
                String(decoding: UnsafeRawBufferPointer(rebasing: raw[0..<length]), as: UTF8.self)
            }
            if name == "." || name == ".." { continue }
            let kind: Kind = switch Int32(entry.pointee.d_type) {
            case DT_DIR: .directory
            case DT_REG: .file
            case DT_LNK: .link
            case DT_UNKNOWN: .unknown
            default: .other
            }
            entries.append((name, kind))
        }
        return entries
    }

    /// `stat` (following links) or `lstat` for entries whose type `readdir` didn't give.
    static func kind(of path: String, followLinks: Bool) -> Kind {
        var info = stat()
        let status = followLinks ? stat(path, &info) : lstat(path, &info)
        guard status == 0 else { return .other }
        switch info.st_mode & S_IFMT {
        case S_IFDIR: return .directory
        case S_IFREG: return .file
        case S_IFLNK: return .link
        default: return .other
        }
    }
}
