import Foundation

extension URL {
    /// The real path (symlinks resolved, `/tmp` → `/private/tmp`), matching what FSEvents reports.
    /// Unlike `resolvingSymlinksInPath()`, it never strips `/private`. Missing items keep their
    /// last component under the canonical parent.
    public var canonical: URL {
        let path = (self.path as NSString).standardizingPath
        guard let resolved = realpath(path, nil) else {
            let parent = deletingLastPathComponent()
            guard parent.path != path, !parent.path.isEmpty, parent.path != "/" || path != "/" else { return URL(fileURLWithPath: path) }
            return parent.canonical.appendingPathComponent(lastPathComponent, isDirectory: hasDirectoryPath)
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: hasDirectoryPath)
    }
}
