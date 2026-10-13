import CoreGraphics
import CoreText
import Foundation

/// The Quick Look thumbnail of a text file: its first lines in a monospaced font on a light portrait page, as Finder
/// shows them in icons, the preview pane and gallery view.
public enum TextThumbnail {
    /// Lines drawn at most; the font is sized so this many fill the page, whatever the file's length.
    public static let lineCount = 40
    /// Bytes read from the file, plenty for `lineCount` lines of code.
    public static let byteLimit = 16 * 1024
    /// Characters kept per line; the page shows about 60, the rest is clipped.
    static let columnLimit = 160
    /// Width over height of the page (US Letter).
    static let pageAspectRatio: CGFloat = 8.5 / 11

    /// The first `maxLines` lines of `text`, with tabs expanded and other control characters removed.
    public static func lines(of text: String, maxLines: Int = lineCount, tabWidth: Int = 4) -> [String] {
        // Character.isNewline covers \n, \r\n, \r and the Unicode line separators.
        text.split(maxSplits: maxLines, omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .prefix(maxLines)
            .map { displayLine($0, tabWidth: tabWidth) }
    }

    private static func displayLine(_ line: Substring, tabWidth: Int) -> String {
        var result = ""
        var column = 0
        for character in line {
            guard column < columnLimit else { break }
            if character == "\t" {
                let spaces = tabWidth - column % tabWidth
                result += String(repeating: " ", count: spaces)
                column += spaces
            } else if character.unicodeScalars.allSatisfy({ $0.properties.generalCategory == .control }) {
                continue
            } else {
                result.append(character)
                column += 1
            }
        }
        return result
    }

    /// The largest portrait page that fits in `maximumSize`, touching its height or width as Quick Look asks.
    public static func pageSize(fitting maximumSize: CGSize) -> CGSize {
        let width = min(maximumSize.width, maximumSize.height * pageAspectRatio)
        return CGSize(width: width.rounded(.down), height: (width / pageAspectRatio).rounded(.down))
    }

    /// Draws the page and `lines` over the whole of `rect` in `context` (Core Graphics coordinates, origin bottom left).
    public static func draw(_ lines: [String], in context: CGContext, rect: CGRect) {
        let margin = (rect.width * 0.06).rounded()
        let lineHeight = (rect.height - 2 * margin) / CGFloat(lineCount)
        let font = CTFontCreateUIFontForLanguage(.userFixedPitch, lineHeight / 1.25, nil)
            ?? CTFontCreateWithName("Menlo" as CFString, lineHeight / 1.25, nil)

        context.saveGState()
        defer { context.restoreGState() }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        let hairline = max(1, rect.width / 512)
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
        context.setLineWidth(hairline)
        context.stroke(rect.insetBy(dx: hairline / 2, dy: hairline / 2))

        context.clip(to: rect.insetBy(dx: margin, dy: margin))
        context.textMatrix = .identity
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.13, alpha: 1),
        ]
        let ascent = CTFontGetAscent(font)
        for (index, text) in lines.prefix(lineCount).enumerated() where !text.isEmpty {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(
                x: rect.minX + margin,
                y: rect.maxY - margin - ascent - CGFloat(index) * lineHeight
            )
            CTLineDraw(line, context)
        }
    }
}
