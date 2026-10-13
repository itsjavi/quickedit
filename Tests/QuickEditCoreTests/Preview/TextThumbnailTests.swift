import CoreGraphics
import Foundation
import ImageIO
@testable import QuickEditCore
import Testing
import UniformTypeIdentifiers

@Suite struct TextThumbnailTests {
    @Test func linesSplitOnEveryNewlineKind() {
        #expect(TextThumbnail.lines(of: "a\nb\r\nc\rd") == ["a", "b", "c", "d"])
        #expect(TextThumbnail.lines(of: "a\n\nb\n") == ["a", "", "b", ""])
        #expect(TextThumbnail.lines(of: "") == [""])
    }

    @Test func linesStopAtTheLimit() {
        let text = (1...100).map(String.init).joined(separator: "\n")
        let lines = TextThumbnail.lines(of: text)
        #expect(lines.count == TextThumbnail.lineCount)
        #expect(lines.last == "40")
        #expect(TextThumbnail.lines(of: "a\nb\nc", maxLines: 2) == ["a", "b"])
    }

    @Test func tabsExpandToTheNextStop() {
        #expect(TextThumbnail.lines(of: "\tx\nab\tc") == ["    x", "ab  c"])
        #expect(TextThumbnail.lines(of: "a\tb", tabWidth: 2) == ["a b"])
    }

    @Test func controlCharactersAreDropped() {
        #expect(TextThumbnail.lines(of: "\u{1B}[31mred\u{1B}[0m\u{7}") == ["[31mred[0m"])
    }

    @Test func longLinesAreClipped() {
        let line = String(repeating: "é", count: 500)
        #expect(TextThumbnail.lines(of: line).first?.count == TextThumbnail.columnLimit)
    }

    @Test func pageIsPortraitAndFits() {
        let square = TextThumbnail.pageSize(fitting: CGSize(width: 512, height: 512))
        #expect(square.height == 512)
        #expect(square.width == (512 * 8.5 / 11).rounded(.down))
        let wide = TextThumbnail.pageSize(fitting: CGSize(width: 1000, height: 200))
        #expect(wide.height == 200)
        let narrow = TextThumbnail.pageSize(fitting: CGSize(width: 100, height: 1000))
        #expect(narrow.width == 100)
        #expect(narrow.height <= 1000)
    }

    /// Renders like the thumbnail extension (a scaled bitmap context) and checks the page is light with dark text at
    /// the top left. Set `THUMBNAIL_OUT=<dir>` to keep the PNG for a look.
    @Test func drawsDarkTextOnALightPage() throws {
        let source = """
            import { defineConfig } from "vite";

            export default defineConfig({
            \tplugins: [react()],
            \tserver: { port: 5173 },
            });
            """
        let size = TextThumbnail.pageSize(fitting: CGSize(width: 256, height: 256))
        let scale = 2
        let width = Int(size.width) * scale
        let height = Int(size.height) * scale
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        TextThumbnail.draw(TextThumbnail.lines(of: source), in: context, rect: context.boundingBoxOfClipPath)

        let image = try #require(context.makeImage())
        let pixels = try #require(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
        func luminance(x: Int, y: Int) -> Int {  // y from the top
            let offset = (y * width + x) * 4
            return (Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3
        }
        // Light page inside the border, below the text.
        #expect(luminance(x: width / 2, y: height - height / 10) > 245)
        // Some dark text pixels in the first line band.
        let firstLine = (height / 16)..<(height / 9)
        let darkPixels = firstLine.reduce(0) { count, y in
            count + (0..<width).filter { luminance(x: $0, y: y) < 128 }.count
        }
        #expect(darkPixels > 20)

        if let directory = ProcessInfo.processInfo.environment["THUMBNAIL_OUT"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("text-thumbnail.png")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
        }
    }
}
