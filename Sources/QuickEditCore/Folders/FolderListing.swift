import Foundation

/// One item in a folder, for the file tree.
public struct FolderEntry: Sendable, Hashable {
    public let url: URL
    public let name: String
    /// A folder, or a symbolic link to one (so it can be expanded).
    public let isDirectory: Bool
    /// The name starts with a dot, or Finder hides it.
    public let isHidden: Bool
    /// Matched by `.gitignore` rules (always true for `.git`).
    public let isIgnored: Bool

    public init(url: URL, name: String, isDirectory: Bool, isHidden: Bool, isIgnored: Bool) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.isIgnored = isIgnored
    }
}

public enum FolderListing {
    /// The children of one folder: folders first, then files, each in Finder's order (`localizedStandardCompare`).
    /// Hidden and ignored items are included and flagged; the tree decides whether to show them. `rules` nil means
    /// nothing is flagged as ignored.
    public static func children(of folder: URL, rules: IgnoreRules?) throws -> [FolderEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .isSymbolicLinkKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys), options: [])

        var context: (folder: String, chain: [GitIgnore], folderIgnored: Bool)?
        if let rules, let relative = rules.relativeToTop(folder), let belowRoot = rules.pathBelowRoot(relative) {
            let folderIgnored = !belowRoot.isEmpty && rules.isIgnored(folder, isDirectory: true)
            context = (relative, folderIgnored ? [] : rules.chain(forFolder: relative), folderIgnored)
        }

        let entries = urls.map { url -> FolderEntry in
            let values = try? url.resourceValues(forKeys: keys)
            let name = url.lastPathComponent
            let isLink = values?.isSymbolicLink == true
            var isDirectory = values?.isDirectory == true
            if isLink {
                isDirectory = (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            var isIgnored = false
            if let rules, let context {
                let path = context.folder.isEmpty ? name : context.folder + "/" + name
                // Like git, a symbolic link is matched as a file even when it points to a folder.
                isIgnored = name == ".git" || context.folderIgnored
                    || rules.evaluate(path, isDirectory: isDirectory && !isLink, chain: context.chain)
            }
            return FolderEntry(
                url: url, name: name, isDirectory: isDirectory,
                isHidden: name.hasPrefix(".") || values?.isHidden == true, isIgnored: isIgnored)
        }
        return entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
