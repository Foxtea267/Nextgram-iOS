import CryptoKit
import Foundation

enum NextgramLyricsHTTP {
    struct StatusError: Error { let code: Int }
    static var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    static func request(host: String, path: String, query: [URLQueryItem] = [], referer: String? = nil) async throws -> Data {
        var url = URLComponents()
        url.scheme = "https"
        url.host = host
        url.path = path
        if !query.isEmpty {
            url.queryItems = query
            url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let address = url.url else { throw URLError(.badURL) }
        var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(referer == nil ? "Nextgram (https://github.com/Foxtea267/Nextgram-iOS)" : "Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        let (bytes, response) = try await self.session.bytes(for: request)
        let limit = NextgramLyrics.maximumFileSize
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else { throw StatusError(code: http.statusCode) }
        guard response.url?.host == host, response.expectedContentLength <= Int64(limit) else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
            if data.count % 4096 == 0 { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        return data
    }
}

public enum NextgramOnlineLyricsProvider: String {
    case qqMusic, netease, amll, lrclib, kugou, betterLyrics
}

public enum NextgramLyricsLookupResult {
    case found(NextgramLyrics)
    case noMatch
    case unavailable
}

public enum NextgramLyricsLookupEvent {
    case invalidMetadata, memoryCache, diskCache, noUsableLyrics, timingMismatch
    case networkError(Int), httpError(Int), invalidResponse
    case candidate(title: String, artist: String, duration: Double?, decision: CandidateDecision)

    public enum CandidateDecision {
        case titleMismatch, artistMismatch, durationMismatch, match
    }
}

public enum NextgramOnlineLyrics {
    typealias LookupTrace = (NextgramLyricsLookupEvent) -> Void

    private struct Artist: Decodable {
        let id: Int64?
        let name: String
        let alias: [String]?
        let trans: String?
        var names: [String] { [self.name] + (self.alias ?? []) + (self.trans.map { [$0] } ?? []) }
    }
    private struct NetEaseArtist: Decodable { let code: Int; let artist: Artist? }
    private struct QQSearch: Decodable {
        struct Result: Decodable {
            struct Body: Decodable {
                struct Songs: Decodable { let list: [QQSong]? }
                let song: Songs?
            }
            struct Payload: Decodable { let body: Body? }
            let code: Int
            let data: Payload?
        }
        let code: Int
        let req_1: Result?
    }
    private struct QQSong: Decodable {
        let mid: String?
        let name: String?
        let title: String?
        let singer: [Artist]?
        let interval: Double?
    }
    private struct QQLyrics: Decodable {
        let code: Int
        let lyric: String?
        let trans: String?
    }
    private struct NetEaseSearch: Decodable {
        struct Result: Decodable { let songs: [Song]? }
        struct Song: Decodable {
            let id: Int64
            let name: String?
            let artists: [Artist]?
            let duration: Double?
            let alias: [String]?
            let transNames: [String]?
        }
        let code: Int
        let result: Result?
    }
    private struct NetEaseLyrics: Decodable {
        struct Text: Decodable { let lyric: String? }
        let code: Int
        let lrc: Text?
        let yrc: Text?
        let tlyric: Text?
        let nolyric: Bool?
    }
    private struct LRCLIBLyrics: Decodable {
        let trackName: String
        let artistName: String
        let duration: Double
        let instrumental: Bool
        let syncedLyrics: String?
        let plainLyrics: String?
    }
    private final class Cached: NSObject {
        let value: NextgramLyrics
        init(_ value: NextgramLyrics) { self.value = value }
    }
    private static let cache: NSCache<NSString, Cached> = {
        let cache = NSCache<NSString, Cached>()
        cache.countLimit = 48
        cache.totalCostLimit = 8 * NextgramLyrics.maximumFileSize
        return cache
    }()

    private struct DiskEntry: Codable {
        let key: String
        let date: Date
        let lyrics: NextgramLyrics
    }

    private static func cacheURL(_ key: String) -> URL? {
        guard let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("NextgramOnlineLyrics-v1", isDirectory: true).appendingPathComponent(name + ".json")
    }

    public static func fetch(provider: NextgramOnlineLyricsProvider, title: String, artist: String, duration: Double) async -> NextgramLyrics? {
        if case let .found(lyrics) = await self.lookup(provider: provider, title: title, artist: artist, duration: duration) { return lyrics }
        return nil
    }

    /// Refresh bypasses successful caches; a failed request never replaces the saved lyrics.
    public static func lookup(provider: NextgramOnlineLyricsProvider, title: String, artist: String, duration: Double,
        forceRefresh: Bool = false) async -> NextgramLyricsLookupResult {
        await self.lookupWithDiagnostics(provider: provider, title: title, artist: artist, duration: duration, forceRefresh: forceRefresh).result
    }

    public static func lookupWithDiagnostics(provider: NextgramOnlineLyricsProvider, title: String, artist: String, duration: Double,
        forceRefresh: Bool = false) async -> (result: NextgramLyricsLookupResult, events: [NextgramLyricsLookupEvent]) {
        var events: [NextgramLyricsLookupEvent] = []
        let result = await self.lookup(provider: provider, title: title, artist: artist, duration: duration, forceRefresh: forceRefresh) { event in
            if case let .candidate(_, _, _, decision) = event, decision != .match, events.count >= 8 {
                return
            }
            events.append(event)
        }
        return (result, events)
    }

    private static func lookup(provider: NextgramOnlineLyricsProvider, title: String, artist: String, duration: Double,
        forceRefresh: Bool, trace: LookupTrace) async -> NextgramLyricsLookupResult {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty, title.utf8.count <= 512, artist.utf8.count <= 512,
              duration.isFinite, duration > 0, duration < 86400 else {
            trace(.invalidMetadata)
            return .noMatch
        }
        guard !Task.isCancelled else { return .noMatch }
        let providerKey = [.amll, .betterLyrics].contains(provider) ? provider.rawValue + "-2" : provider.rawValue
        let key = "\(providerKey)\u{1}\(title)\u{1}\(artist)\u{1}\(Int(duration.rounded()))"
        let url = self.cacheURL(key)
        if !forceRefresh {
            if let cached = self.cache.object(forKey: key as NSString) {
                trace(.memoryCache)
                return .found(cached.value)
            }
            if let url, let file = try? FileHandle(forReadingFrom: url) {
                defer { try? file.close() }
                if let data = try? file.read(upToCount: 4 * NextgramLyrics.maximumFileSize + 1),
                   data.count <= 4 * NextgramLyrics.maximumFileSize,
                   let entry = try? JSONDecoder().decode(DiskEntry.self, from: data), entry.key == key,
                   Date().timeIntervalSince(entry.date) < 30 * 86400 {
                    self.cache.setObject(Cached(entry.lyrics), forKey: key as NSString)
                    trace(.diskCache)
                    return .found(entry.lyrics)
                }
            }
        }
        let result: NextgramLyrics?
        do {
            switch provider {
            case .qqMusic: result = try await self.qqMusic(title: title, artist: artist, duration: duration, trace: trace)
            case .netease: result = try await self.netease(title: title, artist: artist, duration: duration, trace: trace)
            case .amll: result = try await NextgramAMLLLyrics.lookup(title: title, artist: artist, duration: duration, trace: trace)
            case .lrclib: result = try await self.lrclib(title: title, artist: artist, duration: duration, trace: trace)
            case .kugou: result = try await self.kugou(title: title, artist: artist, duration: duration, trace: trace)
            case .betterLyrics: result = try await self.betterLyrics(title: title, artist: artist, duration: duration, trace: trace)
            }
        } catch let error as NextgramLyricsHTTP.StatusError {
            trace(.httpError(error.code))
            return error.code == 404 ? .noMatch : .unavailable
        } catch let error as URLError where error.code != .badServerResponse && error.code != .dataLengthExceedsMaximum && error.code != .badURL {
            trace(.networkError(error.errorCode))
            return .unavailable
        } catch {
            trace(.invalidResponse)
            return .unavailable
        }
        guard !Task.isCancelled else { return .noMatch }
        guard let result else {
            trace(.noUsableLyrics)
            return .noMatch
        }
        if result.isSynced, let end = result.lines.last?.time, end > duration + 5.0 {
            trace(.timingMismatch)
            return .noMatch
        }
        let cost = result.lines.reduce(0) { cost, line in
            cost + line.text.utf8.count + (line.translation?.utf8.count ?? 0) + line.words.count * 32
        }
        self.cache.setObject(Cached(result), forKey: key as NSString, cost: cost)
        if let url, let data = try? JSONEncoder().encode(DiskEntry(key: key, date: Date(), lyrics: result)),
           data.count <= 4 * NextgramLyrics.maximumFileSize {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            // Keep the disk cache bounded, including word timings and translations.
            let files = (try? FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(),
                includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            let oldestFirst = files.sorted {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) <
                ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
            for file in oldestFirst.prefix(max(0, files.count - 48)) { try? FileManager.default.removeItem(at: file) }
        }
        return .found(result)
    }

    private static func qqMusic(title: String, artist: String, duration: Double, trace: LookupTrace) async throws -> NextgramLyrics? {
        let referer = "https://y.qq.com/"
        let encodedQuery = String(decoding: try JSONEncoder().encode(title + " " + artist), as: UTF8.self)
        let payload = #"{"req_1":{"param":{"num_per_page":12,"page_num":1,"query":\#(encodedQuery),"search_type":0},"module":"music.search.SearchCgiService","method":"DoSearchForQQMusicDesktop"}}"#
        let data = try await NextgramLyricsHTTP.request(host: "u6.y.qq.com", path: "/cgi-bin/musicu.fcg",
            query: [URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "data", value: payload)], referer: referer)
        let result = try JSONDecoder().decode(QQSearch.self, from: data)
        guard result.code == 0, let response = result.req_1, response.code == 0 else { throw URLError(.badServerResponse) }
        let songs = (response.data?.body?.song?.list ?? []).filter { song in
            matches(title: title, artist: artist, duration: duration, foundTitle: song.title ?? song.name,
                foundArtists: song.singer?.map(\.name), foundDuration: song.interval, trace: trace)
        }.sorted { abs(($0.interval ?? 0) - duration) < abs(($1.interval ?? 0) - duration) }
        for song in songs.prefix(2) {
            guard let mid = song.mid, !mid.isEmpty else { continue }
            let data = try await NextgramLyricsHTTP.request(host: "c.y.qq.com", path: "/lyric/fcgi-bin/fcg_query_lyric_new.fcg", query: [
                URLQueryItem(name: "songmid", value: mid), URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "nobase64", value: "0")
            ], referer: referer)
            let response = try JSONDecoder().decode(QQLyrics.self, from: data)
            if response.code == 0, let text = decodeQQ(response.lyric), let lyrics = NextgramLyrics.parse(text) {
                return withTranslation(lyrics, text: decodeQQ(response.trans))
            }
        }
        return nil
    }

    private static func decodeQQ(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        if let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
           let decoded = String(data: data, encoding: .utf8), decoded.contains("[") { return decoded }
        return text.hasPrefix("[") ? text : nil
    }

    private static func netease(title: String, artist: String, duration: Double, trace: LookupTrace) async throws -> NextgramLyrics? {
        let referer = "https://music.163.com/"
        let data = try await NextgramLyricsHTTP.request(host: "music.163.com", path: "/api/search/get/web", query: [
            URLQueryItem(name: "s", value: title + " " + artist), URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"), URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "total", value: "true")
        ], referer: referer)
        let response = try JSONDecoder().decode(NetEaseSearch.self, from: data)
        guard response.code == 200 else { throw URLError(.badServerResponse) }
        let songs = (response.result?.songs ?? []).filter { song in
            let names = [song.name].compactMap { $0 } + (song.alias ?? []) + (song.transNames ?? [])
            let titleMatches = names.contains { normalized($0) == normalized(title) }
            let seconds = song.duration.map { $0 / 1000.0 }
            let durationMatches = seconds.map { abs($0 - duration) <= 5.0 } == true
            if !titleMatches || !durationMatches {
                trace(.candidate(title: song.name ?? "", artist: song.artists?.map(\.name).joined(separator: ", ") ?? "",
                    duration: seconds, decision: titleMatches ? .durationMismatch : .titleMismatch))
            }
            return titleMatches && durationMatches
        }.sorted { abs(($0.duration ?? 0) / 1000.0 - duration) < abs(($1.duration ?? 0) / 1000.0 - duration) }
        for song in songs.prefix(2) {
            var artists = song.artists ?? []
            if !artistsMatch(artist, foundArtists: artists.flatMap(\.names)) {
                // Search omits romanised aliases. Resolve only plausible title/duration candidates.
                for (index, candidate) in artists.prefix(4).enumerated() {
                    guard let id = candidate.id else { continue }
                    let data = try await NextgramLyricsHTTP.request(host: "music.163.com", path: "/api/artist/" + String(id), referer: referer)
                    let response = try JSONDecoder().decode(NetEaseArtist.self, from: data)
                    if response.code == 200, let detail = response.artist, detail.id == id { artists[index] = detail }
                }
            }
            let artistMatches = artistsMatch(artist, foundArtists: artists.map(\.name)) ||
                artistsMatch(artist, foundArtists: artists.flatMap(\.names))
            trace(.candidate(title: song.name ?? "", artist: artists.map(\.name).joined(separator: ", "),
                duration: song.duration.map { $0 / 1000.0 }, decision: artistMatches ? .match : .artistMismatch))
            guard artistMatches else { continue }
            let query = [URLQueryItem(name: "id", value: String(song.id))] + ["lv", "kv", "tv", "yv"].map { URLQueryItem(name: $0, value: "-1") }
            let data = try await NextgramLyricsHTTP.request(host: "music.163.com", path: "/api/song/lyric", query: query, referer: referer)
            let response = try JSONDecoder().decode(NetEaseLyrics.self, from: data)
            guard response.code == 200 else { continue }
            if let lyrics = response.yrc?.lyric.flatMap(parseYRC) ?? response.lrc?.lyric.flatMap(NextgramLyrics.parse) {
                return withTranslation(lyrics, text: response.tlyric?.lyric)
            }
            if response.nolyric == true { return NextgramLyrics(lines: [], isSynced: false, instrumental: true) }
        }
        return nil
    }

    private static func lrclib(title: String, artist: String, duration: Double, trace: LookupTrace) async throws -> NextgramLyrics? {
        func lyrics(for response: LRCLIBLyrics) -> NextgramLyrics? {
            guard matches(title: title, artist: artist, duration: duration, foundTitle: response.trackName,
                foundArtists: [response.artistName], foundDuration: response.duration, trace: trace) else { return nil }
            if response.instrumental { return NextgramLyrics(lines: [], isSynced: false, instrumental: true) }
            return response.syncedLyrics.flatMap(NextgramLyrics.parse) ?? response.plainLyrics.flatMap(NextgramLyrics.parse)
        }
        var best: NextgramLyrics?
        var exactError: Error?
        do {
            let data = try await NextgramLyricsHTTP.request(host: "lrclib.net", path: "/api/get", query: [
                URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist),
                URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
            ])
            best = try lyrics(for: JSONDecoder().decode(LRCLIBLyrics.self, from: data))
            if best?.isSynced == true { return best }
        } catch let error as NextgramLyricsHTTP.StatusError where error.code == 404 {
        } catch {
            try Task.checkCancellation()
            exactError = error
        }
        do {
            var query = [URLQueryItem(name: "track_name", value: title)]
            if let primary = artistParts(artist).first, primary != artist {
                query.append(URLQueryItem(name: "artist_name", value: primary))
            }
            let data = try await NextgramLyricsHTTP.request(host: "lrclib.net", path: "/api/search", query: query)
            let candidates = try JSONDecoder().decode([LRCLIBLyrics].self, from: data)
            for response in candidates.sorted(by: { abs($0.duration - duration) < abs($1.duration - duration) }) {
                if let result = lyrics(for: response), best == nil || result.lookupQuality > (best?.lookupQuality ?? 0) {
                    best = result
                }
            }
        } catch {
            try Task.checkCancellation()
            if best == nil { throw exactError ?? error }
        }
        return best
    }

    static func matches(title: String, artist: String, duration: Double, foundTitle: String?, foundArtists: [String]?,
        foundDuration: Double?, trace: LookupTrace) -> Bool {
        let decision: NextgramLyricsLookupEvent.CandidateDecision
        if foundTitle.map(normalized) != normalized(title) {
            decision = .titleMismatch
        } else if !artistsMatch(artist, foundArtists: foundArtists ?? []) {
            decision = .artistMismatch
        } else if foundDuration.map({ $0.isFinite && abs($0 - duration) <= 5.0 }) != true {
            decision = .durationMismatch
        } else {
            decision = .match
        }
        trace(.candidate(title: foundTitle ?? "", artist: foundArtists?.joined(separator: ", ") ?? "", duration: foundDuration, decision: decision))
        return decision == .match
    }

    static func artistsMatch(_ artist: String, foundArtists: [String]) -> Bool {
        let key = normalized(artist)
        guard !key.isEmpty else { return false }
        if foundArtists.contains(where: { normalized($0) == key }) || normalized(foundArtists.joined(separator: " ")) == key { return true }
        let requested = artistParts(artist).map(normalized).filter { !$0.isEmpty }
        let offered = Set(foundArtists.flatMap(artistParts).map(normalized).filter { !$0.isEmpty })
        return Set(requested) == offered || (requested.count > 1 && offered.count == 1 && requested.first.map(offered.contains) == true)
    }

    private static let artistSeparators = try! NSRegularExpression(pattern: #"\s*(?:[,，、;/／&＆]|\bfeat\.?\s|\bft\.?\s|\band\s|\bx\s)\s*"#, options: .caseInsensitive)

    private static func artistParts(_ value: String) -> [String] {
        return artistSeparators.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "\u{1}")
            .components(separatedBy: "\u{1}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func normalized(_ string: String) -> String {
        return string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static let lineTag = try! NSRegularExpression(pattern: #"^\[(\d{1,9}),(\d{1,9})\]"#)
    private static let wordTag = try! NSRegularExpression(pattern: #"\((\d{1,9}),(\d{1,9}),\d+\)"#)

    private static func parseYRC(_ value: String) -> NextgramLyrics? {
        guard value.utf8.count <= NextgramLyrics.maximumFileSize else { return nil }
        var lines: [NextgramLyricLine] = []
        for row in value.components(separatedBy: .newlines) {
            let source = row as NSString
            let range = NSRange(location: 0, length: source.length)
            guard let marker = lineTag.firstMatch(in: row, range: range), let lineTime = Double(source.substring(with: marker.range(at: 1))) else { continue }
            let tags = wordTag.matches(in: row, range: NSRange(location: NSMaxRange(marker.range), length: source.length - NSMaxRange(marker.range)))
            var text = ""
            var words: [NextgramLyricWord] = []
            for (i, tag) in tags.enumerated() {
                let start = NSMaxRange(tag.range)
                let end = i + 1 < tags.count ? tags[i + 1].range.location : source.length
                guard end > start, let time = Double(source.substring(with: tag.range(at: 1))),
                      let duration = Double(source.substring(with: tag.range(at: 2))) else { continue }
                let content = source.substring(with: NSRange(location: start, length: end - start))
                words.append(NextgramLyricWord(time: time / 1000, end: (time + duration) / 1000,
                    range: NSRange(location: text.utf16.count, length: content.utf16.count)))
                text += content
            }
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(NextgramLyricLine(time: lineTime / 1000, text: text, words: words))
            }
            guard lines.count <= 10000 else { return nil }
        }
        return lines.isEmpty ? nil : NextgramLyrics(lines: lines.sorted { ($0.time ?? 0) < ($1.time ?? 0) }, isSynced: true)
    }

    private static func withTranslation(_ lyrics: NextgramLyrics, text: String?) -> NextgramLyrics {
        guard lyrics.isSynced, let translation = text.flatMap(NextgramLyrics.parse), translation.isSynced else { return lyrics }
        return NextgramLyrics(lines: lyrics.lines.map { line in
            guard let time = line.time, let index = translation.currentLineIndex(at: time + 0.25),
                  let start = translation.lines[index].time, abs(start - time) <= 0.25,
                  !translation.lines[index].text.isEmpty, translation.lines[index].text != line.text else { return line }
            return NextgramLyricLine(time: time, text: line.text, words: line.words, translation: translation.lines[index].text)
        }, isSynced: true)
    }
}
