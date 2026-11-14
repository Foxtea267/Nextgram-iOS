import Foundation

enum NextgramLyricsHTTP {
    private static let session: URLSession = {
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
        var request = URLRequest(url: address)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(referer == nil ? "Nextgram (https://github.com/Foxtea267/Nextgram-iOS)" : "Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        let (bytes, response) = try await self.session.bytes(for: request)
        let limit = NextgramLyrics.maximumFileSize
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.url?.host == host, response.expectedContentLength <= Int64(limit) else { throw URLError(.badServerResponse) }
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
    case qqMusic, netease, amll, lrclib
}

public enum NextgramOnlineLyrics {
    private struct Artist: Decodable { let name: String }
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

    public static func fetch(provider: NextgramOnlineLyricsProvider, title: String, artist: String, duration: Double) async -> NextgramLyrics? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty, title.utf8.count <= 512, artist.utf8.count <= 512,
              duration.isFinite, duration > 0, duration < 86400, !Task.isCancelled else { return nil }
        let key = "\(provider.rawValue)\u{1}\(title)\u{1}\(artist)\u{1}\(Int(duration.rounded()))" as NSString
        if let cached = self.cache.object(forKey: key) { return cached.value }
        let result: NextgramLyrics?
        switch provider {
        case .qqMusic: result = try? await self.qqMusic(title: title, artist: artist, duration: duration)
        case .netease: result = try? await self.netease(title: title, artist: artist, duration: duration)
        case .amll: result = await NextgramAMLLLyrics.fetch(title: title, artist: artist, duration: duration)
        case .lrclib: result = try? await self.lrclib(title: title, artist: artist, duration: duration)
        }
        guard !Task.isCancelled, let result else { return nil }
        if result.isSynced, let end = result.lines.last?.time, end > duration + 5.0 { return nil }
        let cost = result.lines.reduce(0) { cost, line in
            let textBytes = line.text.utf8.count + (line.translation?.utf8.count ?? 0)
            return cost + textBytes + line.words.count * 32
        }
        self.cache.setObject(Cached(result), forKey: key, cost: cost)
        return result
    }

    private static func qqMusic(title: String, artist: String, duration: Double) async throws -> NextgramLyrics? {
        let referer = "https://y.qq.com/"
        let encodedQuery = String(decoding: try JSONEncoder().encode(title + " " + artist), as: UTF8.self)
        let payload = #"{"req_1":{"param":{"num_per_page":12,"page_num":1,"query":\#(encodedQuery),"search_type":0},"module":"music.search.SearchCgiService","method":"DoSearchForQQMusicDesktop"}}"#
        let data = try await NextgramLyricsHTTP.request(host: "u6.y.qq.com", path: "/cgi-bin/musicu.fcg",
            query: [URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "data", value: payload)], referer: referer)
        let result = try JSONDecoder().decode(QQSearch.self, from: data)
        guard result.code == 0, let response = result.req_1, response.code == 0 else { return nil }
        let songs = (response.data?.body?.song?.list ?? []).filter { song in
            matches(title: title, artist: artist, duration: duration, foundTitle: song.title ?? song.name,
                foundArtists: song.singer?.map(\.name), foundDuration: song.interval)
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

    private static func netease(title: String, artist: String, duration: Double) async throws -> NextgramLyrics? {
        let referer = "https://music.163.com/"
        let data = try await NextgramLyricsHTTP.request(host: "music.163.com", path: "/api/search/get/web", query: [
            URLQueryItem(name: "s", value: title + " " + artist), URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"), URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "total", value: "true")
        ], referer: referer)
        let response = try JSONDecoder().decode(NetEaseSearch.self, from: data)
        guard response.code == 200 else { return nil }
        let songs = (response.result?.songs ?? []).filter { song in
            matches(title: title, artist: artist, duration: duration, foundTitle: song.name,
                foundArtists: song.artists?.map(\.name), foundDuration: song.duration.map { $0 / 1000.0 })
        }.sorted { abs(($0.duration ?? 0) / 1000.0 - duration) < abs(($1.duration ?? 0) / 1000.0 - duration) }
        for song in songs.prefix(2) {
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

    private static func lrclib(title: String, artist: String, duration: Double) async throws -> NextgramLyrics? {
        let data = try await NextgramLyricsHTTP.request(host: "lrclib.net", path: "/api/get", query: [
            URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
        ])
        let response = try JSONDecoder().decode(LRCLIBLyrics.self, from: data)
        guard matches(title: title, artist: artist, duration: duration, foundTitle: response.trackName,
            foundArtists: [response.artistName], foundDuration: response.duration) else { return nil }
        if response.instrumental { return NextgramLyrics(lines: [], isSynced: false, instrumental: true) }
        return response.syncedLyrics.flatMap(NextgramLyrics.parse) ?? response.plainLyrics.flatMap(NextgramLyrics.parse)
    }

    private static func matches(title: String, artist: String, duration: Double, foundTitle: String?, foundArtists: [String]?, foundDuration: Double?) -> Bool {
        guard let foundTitle, let foundArtists, let foundDuration, foundDuration.isFinite,
              abs(duration - foundDuration) <= 5.0, normalized(title) == normalized(foundTitle) else { return false }
        let key = normalized(artist)
        return !key.isEmpty && (foundArtists.contains { normalized($0) == key } || normalized(foundArtists.joined(separator: " ")) == key)
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
