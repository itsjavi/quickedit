import Foundation

/// Binary property lists open read-only as their XML form.
public enum PropertyListText {
    /// True for data starting with the binary plist magic (`bplist` plus a two-digit version, e.g. `bplist00`).
    public static func isBinaryPropertyList(_ data: Data) -> Bool {
        let magic = Array(data.prefix(8))
        return magic.count == 8 && magic.starts(with: Array("bplist".utf8))
            && magic[6...].allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
    }

    /// The XML property list for a binary one. Throws Foundation's property list error when the data isn't a
    /// readable binary property list (Foundation would otherwise read some garbage as an old-style text plist).
    public static func xmlText(fromBinary data: Data) throws -> String {
        var format = PropertyListSerialization.PropertyListFormat.binary
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        guard format == .binary else { throw CocoaError(.propertyListReadCorrupt) }
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return String(decoding: xml, as: UTF8.self)
    }
}
