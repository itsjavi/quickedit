import Foundation

/// How a linked file shows up in Markdown: `![…](…)` images, `+[…](…)` playable media (NoteMD's embed syntax,
/// which QuickEdit's preview also plays), `[…](…)` anything else.
public enum AttachmentKind: Sendable, Equatable {
    case image, audio, video, file

    public static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "ogg", "flac"]
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm"]
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "bmp", "tif", "tiff", "avif"]

    public init(pathExtension: String) {
        let ext = pathExtension.lowercased()
        if Self.imageExtensions.contains(ext) { self = .image }
        else if Self.audioExtensions.contains(ext) { self = .audio }
        else if Self.videoExtensions.contains(ext) { self = .video }
        else { self = .file }
    }

    /// The kind of a link destination, ignoring any query or fragment.
    public init(destination: String) {
        let path = destination.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? destination
        self.init(pathExtension: (path as NSString).pathExtension)
    }

    var linkPrefix: String {
        switch self {
        case .image: "!"
        case .audio, .video: "+"
        case .file: ""
        }
    }
}

/// Attachment files (voice notes) and the Markdown links pointing at them.
public enum Attachments {
    /// Voice notes of `docs.md` live in `docs.md.assets/` next to it (decision-4).
    public static func assetsFolder(forDocument documentURL: URL) -> URL {
        documentURL.deletingLastPathComponent().appendingPathComponent(documentURL.lastPathComponent + ".assets", isDirectory: true)
    }

    /// The link destination for `fileURL` as written in the document at `documentURL`: relative and percent-encoded.
    public static func destination(for fileURL: URL, fromDocument documentURL: URL) -> String {
        let directory = documentURL.deletingLastPathComponent().standardizedFileURL.path
        let target = fileURL.standardizedFileURL.path
        if target.hasPrefix(directory + "/") {
            return encodeDestination(String(target.dropFirst(directory.count + 1)))
        }
        return encodeDestination(target)
    }

    /// `![name](destination)`, `+[name](destination)` or `[name](destination)` for the file's kind.
    public static func markdownLink(name: String, destination: String, kind: AttachmentKind) -> String {
        "\(kind.linkPrefix)[\(escapeLabel(name))](\(destination))"
    }

    /// Percent-encodes a path for a Markdown link destination (spaces and parentheses included).
    public static func encodeDestination(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    /// Relative path from the folder `fromDirectory` to `target`, both relative to the same root.
    public static func relativePath(fromDirectory: String, to target: String) -> String {
        let from = fromDirectory.split(separator: "/").map(String.init)
        let to = target.split(separator: "/").map(String.init)
        var common = 0
        while common < from.count, common < to.count - 1, from[common] == to[common] { common += 1 }
        return (Array(repeating: "..", count: from.count - common) + to[common...]).joined(separator: "/")
    }

    /// A file URL in `directory` named `fileName`, adding `-2`, `-3`… before the extension when taken.
    public static func uniqueURL(in directory: URL, fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var attempt = 1
        while true {
            let name = attempt == 1 ? base : "\(base)-\(attempt)"
            let url = directory.appendingPathComponent(ext.isEmpty ? name : name + "." + ext)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            attempt += 1
        }
    }

    /// `prefix-2026-10-07-101530.ext` for generated files (recordings, pasted images).
    public static func timestampedName(prefix: String, pathExtension: String, date: Date = Date()) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents(in: .current, from: date)
        let stamp = String(
            format: "%04d-%02d-%02d-%02d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        return "\(prefix)-\(stamp).\(pathExtension)"
    }

    // MARK: Inserting

    /// `line` padded with line breaks so it sits on its own line when inserted at UTF-16 `offset` in `text`.
    public static func ownLine(_ line: String, in text: String, at offset: Int) -> String {
        let ns = text as NSString
        let location = min(max(offset, 0), ns.length)
        let before = location > 0 && ns.character(at: location - 1) != 10 ? "\n" : ""
        let after = location < ns.length && ns.character(at: location) == 10 ? "" : "\n"
        return before + line + after
    }

    /// UTF-16 offset of the end of the first line linking to `destination`, else the end of `text`.
    public static func endOfLine(linking destination: String, in text: String) -> Int {
        let ns = text as NSString
        let candidates = [destination, encodeDestination(destination), "<\(destination)>"].map { "](" + $0 + ")" }
        for candidate in candidates {
            let found = ns.range(of: candidate)
            guard found.location != NSNotFound else { continue }
            let line = ns.lineRange(for: found)
            return NSMaxRange(line) - (ns.substring(with: line).hasSuffix("\n") ? 1 : 0)
        }
        return ns.length
    }

    /// The local file a link destination points at, resolving relative paths against `directory`.
    public static func fileURL(forDestination destination: String, relativeTo directory: URL) -> URL? {
        let raw = destination.hasPrefix("<") && destination.hasSuffix(">") ? String(destination.dropFirst().dropLast()) : destination
        guard !raw.contains("://"), let path = raw.removingPercentEncoding, !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return directory.appendingPathComponent(path).standardizedFileURL
    }

    private static let embedPattern = try! NSRegularExpression(pattern: #"\+\[((?:[^\]\\\n]|\\.)*)\]\((<[^>\n]*>|[^)\s]+)\)"#)

    /// UTF-16 ranges of the first `+[label](…)` embed whose destination is a file named `fileName`, and of
    /// its label. Found by content, so it survives edits, renames and moves of the note.
    public static func embedRanges(linkingFileNamed fileName: String, in text: String) -> (embed: NSRange, label: NSRange)? {
        let ns = text as NSString
        for match in embedPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var destination = ns.substring(with: match.range(at: 2))
            if destination.hasPrefix("<") { destination = String(destination.dropFirst().dropLast()) }
            let path = destination.removingPercentEncoding ?? destination
            if (path as NSString).lastPathComponent == fileName { return (match.range, match.range(at: 1)) }
        }
        return nil
    }

    /// The range to delete to remove `embed` from `text`: its whole line when it stands alone on it.
    public static func removalRange(of embed: NSRange, in text: String) -> NSRange {
        let ns = text as NSString
        let line = ns.lineRange(for: embed)
        let content = ns.substring(with: line).trimmingCharacters(in: .newlines)
        return content == ns.substring(with: embed) ? line : embed
    }

    /// Escapes `label` for use inside `[…]`.
    public static func escapeLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    /// `text` as a Markdown block quote.
    public static func quote(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { "> " + $0 }.joined(separator: "\n")
    }
}
