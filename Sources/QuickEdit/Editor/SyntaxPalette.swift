import AppKit
import QuickEditSyntax

/// Token colours for light and dark appearances. Dynamic colours resolve when drawn, so switching appearance
/// recolours the text without re-highlighting.
enum SyntaxPalette {
    private static func color(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }

    static let keyword = color("syntax.keyword", light: 0x9B2393, dark: 0xFF7AB2)
    static let string = color("syntax.string", light: 0xC41A16, dark: 0xFC6A5D)
    static let stringSpecial = color("syntax.stringSpecial", light: 0xB4540A, dark: 0xFD8F3F)
    static let comment = color("syntax.comment", light: 0x6C7986, dark: 0x7F8C98)
    static let number = color("syntax.number", light: 0x1C00CF, dark: 0xD9C97C)
    static let constant = color("syntax.constant", light: 0x6C36A9, dark: 0xB281EB)
    static let function = color("syntax.function", light: 0x326D74, dark: 0x67B7A4)
    static let type = color("syntax.type", light: 0x0B4F79, dark: 0x5DD8FF)
    static let property = color("syntax.property", light: 0x0F68A0, dark: 0x4EB0CC)
    static let attribute = color("syntax.attribute", light: 0x815F03, dark: 0xCC9768)
    static let link = color("syntax.link", light: 0x0E0EFF, dark: 0x6699FF)
    static let inserted = color("syntax.inserted", light: 0x1A7F37, dark: 0x3FB950)
    static let deleted = color("syntax.deleted", light: 0xCF222E, dark: 0xF85149)
    static let diffMeta = color("syntax.diffMeta", light: 0x8250DF, dark: 0xA371F7)

    /// CSV/TSV columns cycle through these.
    static let columns: [NSColor] = [
        color("syntax.column0", light: 0x0B5CAD, dark: 0x6CB6FF),
        color("syntax.column1", light: 0x1A7F37, dark: 0x57D9A3),
        color("syntax.column2", light: 0xB4540A, dark: 0xFFA657),
        color("syntax.column3", light: 0x8250DF, dark: 0xD2A8FF),
        color("syntax.column4", light: 0x0E7C86, dark: 0x56D4DD),
        color("syntax.column5", light: 0xBF3989, dark: 0xFF9BCE),
    ]

    /// The colour for `kind`; nil leaves the text colour.
    static func color(for kind: TokenKind) -> NSColor? {
        switch kind {
        case .keyword, .tag, .listMarker, .label: keyword
        case .string, .codeSpan: string
        case .stringSpecial: stringSpecial
        case .comment, .quote: comment
        case .number: number
        case .constant, .variableBuiltin, .emphasis: constant
        case .function: function
        case .type, .namespace, .heading: type
        case .property: property
        case .attribute, .strong: attribute
        case .link: link
        case .inserted: inserted
        case .deleted, .invalid: deleted
        case .diffMeta: diffMeta
        case .column(let index): columns[index % columns.count]
        case .variable, .parameter, .operator, .punctuation: nil
        }
    }
}
