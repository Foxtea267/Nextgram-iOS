import Foundation

public struct NextgramLyricWord: Codable, Equatable {
    public let time: Double
    public let end: Double
    public let range: NSRange
}

public struct NextgramLyricLine: Codable, Equatable {
    public let time: Double?
    public let text: String
    public let words: [NextgramLyricWord]
    public let translation: String?

    public init(time: Double?, text: String) {
        self.time = time
        self.text = text
        self.words = []
        self.translation = nil
    }

    init(time: Double?, text: String, words: [NextgramLyricWord], translation: String? = nil) {
        self.time = time
        self.text = text
        self.words = words
        self.translation = translation
    }
}

public struct NextgramLyrics: Codable, Equatable {
    public static let maximumFileSize = 1024 * 1024

    public let lines: [NextgramLyricLine]
    public let isSynced: Bool
    public let instrumental: Bool

    public init(lines: [NextgramLyricLine], isSynced: Bool, instrumental: Bool = false) {
        self.lines = lines
        self.isSynced = isSynced
        self.instrumental = instrumental
    }

    private static let timestamp = try! NSRegularExpression(pattern: #"\[([0-9]{1,4}):([0-5]?[0-9])(?:[.:]([0-9]{1,3}))?\]"#)
    private static let wordTimestamp = try! NSRegularExpression(pattern: #"<[0-9]{1,4}:[0-5]?[0-9](?:[.:][0-9]{1,3})?>"#)
    private static let metadata = try! NSRegularExpression(pattern: #"^\[[A-Za-z][A-Za-z0-9_-]*:.*\]$"#)
    private static let offsetTag = try! NSRegularExpression(pattern: #"^\[offset:\s*([+-]?[0-9]+)\s*\]$"#, options: .caseInsensitive)

    public static func parse(_ text: String) -> NextgramLyrics? {
        guard !text.isEmpty, text.utf8.count <= Self.maximumFileSize else { return nil }
        let start = text.prefix(200).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
        if start.hasPrefix("<?xml") || start.hasPrefix("<tt ") || start.hasPrefix("<tt>") {
            return NextgramTTMLParser.parse(text)?.lyrics
        }
        let rows = text.replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        guard rows.count <= 10000 else { return nil }
        var offset = 0.0
        for row in rows {
            let value = row.trimmingCharacters(in: .whitespaces)
            let range = NSRange(value.startIndex..., in: value)
            if let match = Self.offsetTag.firstMatch(in: value, range: range),
               let amount = Range(match.range(at: 1), in: value), let milliseconds = Double(value[amount]), milliseconds.isFinite {
                offset = milliseconds / 1000.0
            }
        }

        var timed: [(time: Double, text: String, order: Int)] = []
        var plain: [String] = []
        for row in rows {
            let value = row.trimmingCharacters(in: .whitespaces)
            let source = value as NSString
            let range = NSRange(location: 0, length: source.length)
            if Self.metadata.firstMatch(in: value, range: range) != nil { continue }
            var cursor = 0
            var times: [Double] = []
            while cursor < source.length, let match = Self.timestamp.firstMatch(in: value, options: .anchored,
                range: NSRange(location: cursor, length: source.length - cursor)) {
                let minutes = Double(source.substring(with: match.range(at: 1))) ?? 0.0
                let seconds = Double(source.substring(with: match.range(at: 2))) ?? 0.0
                let fractionRange = match.range(at: 3)
                let fraction = fractionRange.location == NSNotFound ? 0.0 : Double("0." + source.substring(with: fractionRange)) ?? 0.0
                // Positive LRC offset advances the lyric relative to its recorded timestamp.
                times.append(max(0.0, minutes * 60.0 + seconds + fraction - offset))
                cursor = NSMaxRange(match.range)
                guard times.count <= 100 else { return nil }
            }
            if times.isEmpty {
                plain.append(value)
            } else {
                let body = source.substring(from: cursor)
                let lyric = Self.wordTimestamp.stringByReplacingMatches(in: body,
                    range: NSRange(body.startIndex..., in: body), withTemplate: "").trimmingCharacters(in: .whitespaces)
                for time in times {
                    timed.append((time, lyric, timed.count))
                }
                guard timed.count <= 10000 else { return nil }
            }
        }
        if !timed.isEmpty {
            timed.sort { $0.time == $1.time ? $0.order < $1.order : $0.time < $1.time }
            var lines: [NextgramLyricLine] = []
            for line in timed {
                if let last = lines.last, last.time == line.time {
                    if !line.text.isEmpty && last.text != line.text {
                        lines[lines.count - 1] = NextgramLyricLine(time: line.time,
                            text: last.text.isEmpty ? line.text : last.text + "\n" + line.text)
                    }
                } else if !line.text.isEmpty || lines.last?.text.isEmpty == false {
                    lines.append(NextgramLyricLine(time: line.time, text: line.text))
                }
            }
            while lines.last?.text.isEmpty == true { lines.removeLast() }
            guard !lines.isEmpty else { return nil }
            return NextgramLyrics(lines: lines, isSynced: true)
        }
        var lines: [NextgramLyricLine] = []
        for line in plain where !line.isEmpty || lines.last?.text.isEmpty == false {
            lines.append(NextgramLyricLine(time: nil, text: line))
        }
        while lines.last?.text.isEmpty == true { lines.removeLast() }
        return lines.isEmpty ? nil : NextgramLyrics(lines: lines, isSynced: false)
    }

    public func currentLineIndex(at timestamp: Double) -> Int? {
        guard self.isSynced, timestamp.isFinite else { return nil }
        var lower = 0
        var upper = self.lines.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if let time = self.lines[middle].time, time <= timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower == 0 ? nil : lower - 1
    }
}

public enum NextgramLyricsStore {
    public enum StoreError: Error {
        case invalidLyrics
    }

    private static func url(fileId: Int64) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("NextgramLyrics", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(String(fileId) + ".lrc")
    }

    public static func load(fileId: Int64) -> NextgramLyrics? {
        guard let url = try? Self.url(fileId: fileId), let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: NextgramLyrics.maximumFileSize + 1),
              data.count <= NextgramLyrics.maximumFileSize, let text = String(data: data, encoding: .utf8) else { return nil }
        return NextgramLyrics.parse(text)
    }

    public static func save(text: String, fileId: Int64) throws {
        guard NextgramLyrics.parse(text) != nil else { throw StoreError.invalidLyrics }
        try Data(text.utf8).write(to: Self.url(fileId: fileId), options: .atomic)
    }

    public static func remove(fileId: Int64) throws {
        let url = try Self.url(fileId: fileId)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
