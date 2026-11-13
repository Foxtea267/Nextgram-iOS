import Foundation

public struct NextgramLyricLine: Equatable {
    public let time: Double?
    public let text: String

    public init(time: Double?, text: String) {
        self.time = time
        self.text = text
    }
}

public struct NextgramLyrics: Equatable {
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

private final class NextgramLyricsCacheEntry {
    let lyrics: NextgramLyrics

    init(_ lyrics: NextgramLyrics) {
        self.lyrics = lyrics
    }
}

private final class NextgramLyricsSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    weak var owner: NextgramLyricsService?

    init(owner: NextgramLyricsService) {
        self.owner = owner
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let allowed = (response as? HTTPURLResponse)?.statusCode == 200
            && response.expectedContentLength <= Int64(NextgramLyrics.maximumFileSize)
        completionHandler(allowed ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        self.owner?.received(data, task: dataTask)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        self.owner?.completed(task: task, error: error)
    }
}

public final class NextgramLyricsService {
    public static let shared = NextgramLyricsService()

    private struct Response: Decodable {
        let trackName: String
        let artistName: String
        let duration: Double
        let instrumental: Bool
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private struct Request {
        let title: String
        let artist: String
        let duration: Double
        let key: String
        let completion: (NextgramLyrics?) -> Void
        var data = Data()
    }

    private let lock = NSLock()
    private var requests: [Int: Request] = [:]
    private let cache = NSCache<NSString, NextgramLyricsCacheEntry>()
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15.0
        configuration.timeoutIntervalForResource = 20.0
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: NextgramLyricsSessionDelegate(owner: self), delegateQueue: nil)
    }()

    private init() {
        self.cache.countLimit = 32
        self.cache.totalCostLimit = 8 * NextgramLyrics.maximumFileSize
    }

    private static func normalized(_ value: String) -> String {
        return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // The caller requests online lookup explicitly before sending track metadata to LRCLIB.
    @discardableResult
    public func fetch(title: String, artist: String, duration: Double,
        completion: @escaping (NextgramLyrics?) -> Void) -> URLSessionDataTask? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = Self.normalized(title)
        let normalizedArtist = Self.normalized(artist)
        let unknownTitles: Set<String> = ["unknown", "unknown title", "unknown track", "未知标题", "未知歌曲"]
        let unknownArtists: Set<String> = ["unknown", "unknown artist", "未知艺术家", "未知歌手"]
        guard !title.isEmpty, !artist.isEmpty, !unknownTitles.contains(normalizedTitle), !unknownArtists.contains(normalizedArtist),
              title.utf8.count <= 512, artist.utf8.count <= 512, duration.isFinite, duration > 0.0, duration < 86400.0 else {
            DispatchQueue.main.async { completion(nil) }
            return nil
        }
        let key = normalizedTitle + "\u{1}" + normalizedArtist + "\u{1}" + String(Int(duration.rounded()))
        if let cached = self.cache.object(forKey: key as NSString) {
            DispatchQueue.main.async { completion(cached.lyrics) }
            return nil
        }
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist), URLQueryItem(name: "duration", value: String(Int(duration.rounded())))]
        guard let url = components.url else {
            DispatchQueue.main.async { completion(nil) }
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Nextgram (https://github.com/Foxtea267/Nextgram-iOS)", forHTTPHeaderField: "User-Agent")
        self.lock.lock()
        let task = self.session.dataTask(with: request)
        self.requests[task.taskIdentifier] = Request(title: title, artist: artist, duration: duration, key: key, completion: completion)
        self.lock.unlock()
        task.resume()
        return task
    }

    fileprivate func received(_ data: Data, task: URLSessionDataTask) {
        self.lock.lock()
        guard var request = self.requests[task.taskIdentifier] else {
            self.lock.unlock()
            return
        }
        let allowed = data.count <= NextgramLyrics.maximumFileSize - request.data.count
        if allowed {
            request.data.append(data)
            self.requests[task.taskIdentifier] = request
        }
        self.lock.unlock()
        if !allowed { task.cancel() }
    }

    fileprivate func completed(task: URLSessionTask, error: Error?) {
        self.lock.lock()
        let request = self.requests.removeValue(forKey: task.taskIdentifier)
        self.lock.unlock()
        guard let request else { return }
        var lyrics: NextgramLyrics?
        if error == nil, let response = try? JSONDecoder().decode(Response.self, from: request.data),
           Self.normalized(response.trackName) == Self.normalized(request.title),
           Self.normalized(response.artistName) == Self.normalized(request.artist),
           response.duration.isFinite, abs(response.duration - request.duration) <= 3.0 {
            if response.instrumental {
                lyrics = NextgramLyrics(lines: [], isSynced: false, instrumental: true)
            } else {
                lyrics = response.syncedLyrics.flatMap(NextgramLyrics.parse) ?? response.plainLyrics.flatMap(NextgramLyrics.parse)
            }
        }
        if let lyrics {
            self.cache.setObject(NextgramLyricsCacheEntry(lyrics), forKey: request.key as NSString, cost: request.data.count)
        }
        let result = lyrics
        DispatchQueue.main.async { request.completion(result) }
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
