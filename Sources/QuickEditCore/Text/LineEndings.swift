import Foundation

public enum LineEnding: String, CaseIterable, Sendable {
    case lf = "\n"
    case crlf = "\r\n"
    case cr = "\r"

    public var displayName: String {
        switch self {
        case .lf: "LF"
        case .crlf: "CRLF"
        case .cr: "CR"
        }
    }
}

public struct LineEndingInfo: Equatable, Sendable {
    /// The most frequent ending (ties prefer LF, then CRLF); `.lf` when the text has no line breaks.
    public let dominant: LineEnding
    /// More than one kind of line ending occurs.
    public let isMixed: Bool
    /// Occurrences of each kind; every case has an entry, zero included.
    public let counts: [LineEnding: Int]

    public init(dominant: LineEnding, isMixed: Bool, counts: [LineEnding: Int]) {
        self.dominant = dominant
        self.isMixed = isMixed
        self.counts = counts
    }
}

public enum LineEndings {
    public static func detect(_ text: String) -> LineEndingInfo {
        var lf = 0, crlf = 0, cr = 0
        text.withUTF8Buffer { bytes in
            let count = bytes.count
            var index = 0
            while index < count {
                let byte = bytes[index]
                if byte == 0x0A {
                    lf += 1
                } else if byte == 0x0D {
                    if index + 1 < count, bytes[index + 1] == 0x0A {
                        crlf += 1
                        index += 1
                    } else {
                        cr += 1
                    }
                }
                index += 1
            }
        }
        let counts: [LineEnding: Int] = [.lf: lf, .crlf: crlf, .cr: cr]
        var dominant = LineEnding.lf
        for ending in LineEnding.allCases where counts[ending]! > counts[dominant]! {
            dominant = ending
        }
        let kinds = [lf, crlf, cr].filter { $0 > 0 }.count
        return LineEndingInfo(dominant: dominant, isMixed: kinds > 1, counts: counts)
    }

    /// Replaces every LF, CRLF and CR with `ending`. Nothing else changes.
    public static func convert(_ text: String, to ending: LineEnding) -> String {
        let info = detect(text)
        if !info.isMixed, info.dominant == ending || info.counts.values.allSatisfy({ $0 == 0 }) { return text }
        let replacement = Array(ending.rawValue.utf8)
        return text.withUTF8Buffer { bytes in
            var output = [UInt8]()
            output.reserveCapacity(bytes.count + (ending == .crlf ? info.counts[.lf]! + info.counts[.cr]! : 0))
            let count = bytes.count
            var index = 0
            var runStart = 0
            while index < count {
                let byte = bytes[index]
                if byte == 0x0A || byte == 0x0D {
                    output.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[runStart..<index]))
                    output.append(contentsOf: replacement)
                    if byte == 0x0D, index + 1 < count, bytes[index + 1] == 0x0A { index += 1 }
                    runStart = index + 1
                }
                index += 1
            }
            output.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[runStart..<count]))
            return String(decoding: output, as: UTF8.self)
        }
    }
}

extension String {
    /// Runs `body` over contiguous UTF-8 without copying native strings (bridged ones are made contiguous once).
    func withUTF8Buffer<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
        var copy = self
        return try copy.withUTF8(body)
    }
}
