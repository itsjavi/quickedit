import Foundation
import Synchronization

/// Quick Open's fuzzy matcher: the query's characters must appear in order in the path (ASCII case-insensitively;
/// whitespace in the query is ignored). The best alignment is scored with bonuses for characters in the file name,
/// at word starts (after `/`, `-`, `_`, `.`, space, or a lower-to-upper camelCase change) and in consecutive runs,
/// and small penalties for gaps.
public enum FuzzyMatcher {
    public struct Match: Equatable, Sendable {
        public let path: String
        public let score: Int
        /// UTF-16 offsets of the matched characters in `path`, ascending, for highlighting.
        public let matches: [Int]

        public init(path: String, score: Int, matches: [Int]) {
            self.path = path
            self.score = score
            self.matches = matches
        }
    }

    /// The best `limit` matches, best first (ties: shorter path, then alphabetical). An empty query returns the
    /// first `limit` candidates unscored. Large candidate lists are scored on several cores.
    public static func match(_ query: String, in candidates: [String], limit: Int) -> [Match] {
        guard limit > 0 else { return [] }
        let needle = foldedQuery(query)
        if needle.isEmpty {
            return candidates.prefix(limit).map { Match(path: $0, score: 0, matches: []) }
        }

        let chunkCount = min(ProcessInfo.processInfo.activeProcessorCount * 2, max(1, candidates.count / 4_000))
        var best = TopK(limit: limit)
        if chunkCount <= 1 {
            best = topMatches(needle, candidates, 0..<candidates.count, limit: limit)
        } else {
            let partial = Mutex<[TopK]>([])
            let chunkSize = (candidates.count + chunkCount - 1) / chunkCount
            DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
                let range = (chunk * chunkSize)..<min(candidates.count, (chunk + 1) * chunkSize)
                let top = topMatches(needle, candidates, range, limit: limit)
                partial.withLock { $0.append(top) }
            }
            for top in partial.withLock({ $0 }) {
                for entry in top.entries { best.insert(entry, candidates: candidates) }
            }
        }

        let scorer = Scorer(query: needle)
        return best.entries.map { entry in
            let path = candidates[entry.index]
            var bytes = path
            let positions = bytes.withUTF8 { scorer.positions($0) }
            return Match(path: path, score: entry.score, matches: utf16Offsets(of: positions, in: path))
        }
    }

    /// Scores one candidate; nil when the query isn't a subsequence of it.
    public static func score(_ query: String, _ candidate: String) -> Match? {
        let needle = foldedQuery(query)
        guard !needle.isEmpty else { return Match(path: candidate, score: 0, matches: []) }
        let scorer = Scorer(query: needle)
        var path = candidate
        return path.withUTF8 { bytes in
            guard let score = scorer.score(bytes) else { return nil }
            return Match(path: candidate, score: score, matches: utf16Offsets(of: scorer.positions(bytes), in: candidate))
        }
    }

    private static func topMatches(_ needle: [UInt8], _ candidates: [String], _ range: Range<Int>, limit: Int) -> TopK {
        let scorer = Scorer(query: needle)
        var top = TopK(limit: limit)
        for index in range {
            var path = candidates[index]
            if let score = path.withUTF8({ scorer.score($0) }) {
                top.insert(TopK.Entry(score: score, length: path.utf8.count, index: index), candidates: candidates)
            }
        }
        return top
    }

    // MARK: - Scoring

    static let scoreMatch: Int32 = 16
    static let gapStart: Int32 = 3
    static let gapExtension: Int32 = 1
    static let bonusPathStart: Int32 = 10
    static let bonusSeparator: Int32 = 8
    static let bonusCamelCase: Int32 = 7
    static let bonusConsecutive: Int32 = 5
    static let bonusFileName: Int32 = 6

    static func foldedQuery(_ query: String) -> [UInt8] {
        query.utf8.compactMap { byte in
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D: nil
            case 0x41...0x5A: byte | 0x20
            default: byte
            }
        }
    }

    @inline(__always) static func fold(_ byte: UInt8) -> UInt8 {
        byte >= 0x41 && byte <= 0x5A ? byte | 0x20 : byte
    }

    /// A Smith-Waterman-style alignment (like fzf's v2 algorithm) restricted to the span between the first and last
    /// possible positions of each query character. One scorer per thread; its buffers are reused across candidates.
    final class Scorer {
        static let impossible = Int32.min / 2

        private let query: UnsafeMutableBufferPointer<UInt8>
        private let firstPositions: UnsafeMutableBufferPointer<Int>
        private let lastPositions: UnsafeMutableBufferPointer<Int>
        private var capacity = 0
        private var bonus = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        private var previous = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        private var current = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        /// Bonus of the first character of the consecutive run ending at each cell.
        private var previousRun = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        private var currentRun = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

        init(query: [UInt8]) {
            self.query = .allocate(capacity: query.count)
            _ = self.query.initialize(from: query)
            firstPositions = .allocate(capacity: query.count)
            lastPositions = .allocate(capacity: query.count)
        }

        deinit {
            query.deallocate()
            firstPositions.deallocate()
            lastPositions.deallocate()
            for buffer in [bonus, previous, current, previousRun, currentRun] { buffer.deallocate() }
        }

        /// The best alignment score, or nil when the query isn't a subsequence of `text`.
        func score(_ text: UnsafeBufferPointer<UInt8>) -> Int? {
            guard text.count >= query.count, bounds(text) else { return nil }
            prepare(text)
            fill(text, table: nil)
            let row = query.count - 1
            var best = Self.impossible
            for column in firstPositions[row]...lastPositions[row] where previous[column] > best { best = previous[column] }
            return Int(best)
        }

        /// Byte offsets of the best alignment; empty when the query doesn't match.
        func positions(_ text: UnsafeBufferPointer<UInt8>) -> [Int] {
            guard text.count >= query.count, bounds(text) else { return [] }
            prepare(text)
            let width = text.count
            var table = Table(
                score: Array(repeating: Self.impossible, count: query.count * width),
                fromDiagonal: Array(repeating: false, count: query.count * width),
                gapOrigin: Array(repeating: -1, count: query.count * width))
            fill(text, table: &table)

            var row = query.count - 1
            var column = firstPositions[row]
            for candidate in firstPositions[row]...lastPositions[row]
            where table.score[row * width + candidate] > table.score[row * width + column] {
                column = candidate
            }
            var result = Array(repeating: 0, count: query.count)
            while true {
                result[row] = column
                if row == 0 { break }
                let cell = row * width + column
                column = table.fromDiagonal[cell] ? column - 1 : Int(table.gapOrigin[cell])
                row -= 1
            }
            return result
        }

        struct Table {
            var score: [Int32]
            var fromDiagonal: [Bool]
            var gapOrigin: [Int32]
        }

        /// The span each query character can occupy: greedy from the left and from the right.
        private func bounds(_ text: UnsafeBufferPointer<UInt8>) -> Bool {
            var position = 0
            for index in 0..<query.count {
                let character = query[index]
                while position < text.count, FuzzyMatcher.fold(text[position]) != character { position += 1 }
                if position == text.count { return false }
                firstPositions[index] = position
                position += 1
            }
            position = text.count - 1
            for index in stride(from: query.count - 1, through: 0, by: -1) {
                let character = query[index]
                while FuzzyMatcher.fold(text[position]) != character { position -= 1 }
                lastPositions[index] = position
                position -= 1
            }
            return true
        }

        private func prepare(_ text: UnsafeBufferPointer<UInt8>) {
            if capacity < text.count {
                capacity = max(text.count, capacity * 2, 64)
                for buffer in [bonus, previous, current, previousRun, currentRun] { buffer.deallocate() }
                bonus = .allocate(capacity: capacity)
                previous = .allocate(capacity: capacity)
                current = .allocate(capacity: capacity)
                previousRun = .allocate(capacity: capacity)
                currentRun = .allocate(capacity: capacity)
            }
            var nameStart = text.count
            while nameStart > 0, text[nameStart - 1] != UInt8(ascii: "/") { nameStart -= 1 }
            var last = UInt8(ascii: "/")
            // Only the span the query can occupy needs bonuses.
            for index in 0...lastPositions[query.count - 1] {
                let byte = text[index]
                if index >= firstPositions[0] {
                    var value: Int32
                    switch last {
                    case UInt8(ascii: "/"): value = FuzzyMatcher.bonusPathStart
                    case UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: " "): value = FuzzyMatcher.bonusSeparator
                    case 0x61...0x7A where byte >= 0x41 && byte <= 0x5A: value = FuzzyMatcher.bonusCamelCase
                    default: value = 0
                    }
                    if index >= nameStart { value += FuzzyMatcher.bonusFileName }
                    bonus[index] = value
                }
                last = byte
            }
        }

        /// Row by row; afterwards `previous` holds the last row. Like fzf, a character continuing a run gets at least
        /// the bonus of the run's first character (so a whole word after `/` scores like its start), unless it starts
        /// a better word itself.
        private func fill(_ text: UnsafeBufferPointer<UInt8>, table: UnsafeMutablePointer<Table>?) {
            let width = text.count
            for row in 0..<query.count {
                let character = query[row]
                let low = firstPositions[row], high = lastPositions[row]
                let firstBonusFactor: Int32 = row == 0 ? 2 : 1
                let previousLow = row > 0 ? firstPositions[row - 1] : 0
                let previousHigh = row > 0 ? lastPositions[row - 1] : -1
                // Best "previous row score minus gap penalty" over columns at least two to the left.
                var gapBest = Self.impossible
                var gapBestColumn: Int32 = -1
                let start = row == 0 ? low : min(low, previousLow + 2)
                for column in start...high {
                    if row > 0 {
                        let origin = column - 2
                        if origin >= previousLow, origin <= previousHigh,
                           previous[origin] - FuzzyMatcher.gapStart > gapBest - FuzzyMatcher.gapExtension {
                            gapBest = previous[origin] - FuzzyMatcher.gapStart
                            gapBestColumn = Int32(origin)
                        } else if gapBest > Self.impossible {
                            gapBest -= FuzzyMatcher.gapExtension
                        }
                    }
                    if column < low { continue }
                    var value = Self.impossible
                    var diagonal = false
                    var origin: Int32 = -1
                    let own = bonus[column]
                    var run = own
                    if FuzzyMatcher.fold(text[column]) == character {
                        if row == 0 {
                            value = FuzzyMatcher.scoreMatch + own * firstBonusFactor
                        } else {
                            if column - 1 >= previousLow, column - 1 <= previousHigh, previous[column - 1] > Self.impossible {
                                let runStart = previousRun[column - 1]
                                let startsWord = own >= FuzzyMatcher.bonusSeparator && own > runStart
                                let consecutive = startsWord ? own : max(own, FuzzyMatcher.bonusConsecutive, runStart)
                                value = previous[column - 1] + FuzzyMatcher.scoreMatch + consecutive
                                diagonal = true
                                run = startsWord ? own : runStart
                            }
                            if gapBest > Self.impossible, gapBest + FuzzyMatcher.scoreMatch + own > value {
                                value = gapBest + FuzzyMatcher.scoreMatch + own
                                diagonal = false
                                origin = gapBestColumn
                                run = own
                            }
                        }
                    }
                    current[column] = value
                    currentRun[column] = run
                    if let table {
                        table.pointee.score[row * width + column] = value
                        table.pointee.fromDiagonal[row * width + column] = diagonal
                        table.pointee.gapOrigin[row * width + column] = origin
                    }
                }
                // `current` becomes the next row's `previous`; cells outside each row's span are never read.
                swap(&previous, &current)
                swap(&previousRun, &currentRun)
            }
        }
    }

    /// Keeps the best `limit` entries by (score desc, length asc, path asc), best first.
    struct TopK: Sendable {
        struct Entry: Sendable { let score: Int; let length: Int; let index: Int }
        let limit: Int
        private(set) var entries: [Entry] = []

        init(limit: Int) { self.limit = limit }

        static func isBetter(_ a: Entry, _ b: Entry, _ candidates: [String]) -> Bool {
            if a.score != b.score { return a.score > b.score }
            if a.length != b.length { return a.length < b.length }
            if candidates[a.index] != candidates[b.index] { return candidates[a.index] < candidates[b.index] }
            return a.index < b.index
        }

        mutating func insert(_ entry: Entry, candidates: [String]) {
            if entries.count == limit {
                guard Self.isBetter(entry, entries[entries.count - 1], candidates) else { return }
                entries.removeLast()
            }
            var low = 0, high = entries.count
            while low < high {
                let mid = (low + high) / 2
                if Self.isBetter(entries[mid], entry, candidates) { low = mid + 1 } else { high = mid }
            }
            entries.insert(entry, at: low)
        }
    }

    /// Converts UTF-8 byte offsets to UTF-16 offsets (identical for ASCII paths). Several bytes of one character
    /// give one offset.
    static func utf16Offsets(of byteOffsets: [Int], in path: String) -> [Int] {
        if path.utf8.count == path.utf16.count { return byteOffsets }
        var result: [Int] = []
        var targets = byteOffsets[...]
        var utf8Offset = 0, utf16Offset = 0
        for scalar in path.unicodeScalars {
            let width = UTF8.width(scalar)
            var hit = false
            while let target = targets.first, target < utf8Offset + width {
                if target >= utf8Offset { hit = true }
                targets.removeFirst()
            }
            if hit { result.append(utf16Offset) }
            if targets.isEmpty { break }
            utf8Offset += width
            utf16Offset += UTF16.width(scalar)
        }
        return result
    }
}
