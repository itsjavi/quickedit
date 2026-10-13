import Foundation

/// A minimal HTML page showing a `TextPreview` as monospaced plain text, for the Quick Look extension.
///
/// Quick Look's `.plainText` replies can't choose a font, so the extension returns this page: escaped text in a `<pre>`,
/// no highlighting, following the system light/dark appearance, with a note when the file was truncated.
public enum TextPreviewHTML {
    public static func document(for preview: TextPreview, totalByteCount: Int? = nil) -> String {
        var note = ""
        if preview.isTruncated {
            let shown = ByteCountFormatter.string(fromByteCount: Int64(preview.text.utf8.count), countStyle: .file)
            let total = totalByteCount.map {
                " of " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? ""
            note = "<p class=\"note\">Showing the first \(shown)\(total). Open the file in QuickEdit to see all of it.</p>\n"
        }
        return """
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="color-scheme" content="light dark">
            <style>
            :root { color-scheme: light dark; }
            body { margin: 0; padding: 12px 16px; background: Canvas; color: CanvasText; }
            pre { margin: 0; font: 12px/1.45 ui-monospace, "SF Mono", Menlo, monospace; tab-size: 4;
                  white-space: pre-wrap; overflow-wrap: anywhere; }
            .note { margin: 0 0 12px; font: 12px -apple-system, sans-serif; color: GrayText; }
            </style>
            </head>
            <body>
            \(note)<pre>\(escaped(preview.text))</pre>
            </body>
            </html>

            """
    }

    static func escaped(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for character in text.unicodeScalars {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.unicodeScalars.append(character)
            }
        }
        return result
    }
}
