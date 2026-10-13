import Foundation
import UniformTypeIdentifiers

enum PreviewLinks {
    /// Whether a linked local file opens in QuickEdit (text and source files) rather than being shown in Finder.
    /// Other files are never launched from a link: they could be executables.
    static func opensInEditor(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return false }
        if let type = UTType(filenameExtension: url.pathExtension), !type.isDynamic {
            return type.conforms(to: .text) || type.conforms(to: .sourceCode)
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return !((try? handle.read(upToCount: 8192)) ?? Data()).contains(0)
    }
}
