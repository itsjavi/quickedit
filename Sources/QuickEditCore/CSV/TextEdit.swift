import Foundation

/// A replacement of a UTF-16 range in the current text, as `NSTextStorage.replaceCharacters(in:with:)` takes it.
public struct TextEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String

    public init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }

    /// True when applying the edit leaves the text unchanged.
    public var isEmpty: Bool { range.length == 0 && replacement.isEmpty }

    public func apply(to text: NSMutableString) {
        text.replaceCharacters(in: range, with: replacement)
    }
}
