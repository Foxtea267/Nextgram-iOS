import CryptoKit
import Foundation

// Host-only regression executable. Build alongside Sources/*.swift; no account or live network.
private final class LyricsProtocol: URLProtocol {
    static var status = 200
    static var count = 0
    static var title = ""
    static var responseArtist = "Singer B / Singer A"
    static var responseDuration = 200.0
    static var neteaseFixture = false
    static var networkFailure = false
    static var collaborationFixture = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.count += 1
        if Self.networkFailure {
            self.client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        var body: [String: Any] = ["trackName": Self.title, "artistName": Self.responseArtist,
            "duration": Self.responseDuration, "instrumental": false,
            "syncedLyrics": "[00:01.00]cached line\n[00:03.00]second line"]
        if Self.neteaseFixture {
            switch self.request.url!.path {
            case "/api/search/get/web":
                body = ["code": 200, "result": ["songs": [["id": 12345, "name": "別の表記", "alias": [Self.title],
                    "duration": 200000, "artists": [["id": 67890, "name": "別名"]]]]]]
            case "/api/artist/67890": body = ["code": 200, "artist": ["id": 67890, "name": "別名", "alias": ["Singer A & Singer B"]]]
            case "/api/song/lyric": body = ["code": 200, "lrc": ["lyric": "[00:01.00]alias match"]]
            default: fatalError("Unexpected NetEase request")
            }
        }
        if self.request.url?.host == "lyrics.kugou.com" {
            if self.request.url?.path == "/search" {
                body = ["status": 200, "candidates": [[
                    "id": "42", "accesskey": "local-test", "song": Self.title, "singer": Self.responseArtist, "duration": 200_000
                ]]]
            } else {
                let content = Data("[00:01.00]KuGou fixture".utf8).base64EncodedString()
                body = ["status": 200, "content": content]
            }
        } else if self.request.url?.host == "api.betterlyrics.org" {
            body = ["ttml": "<tt><body dur=\"200s\"><div><p begin=\"1s\" end=\"3s\"><span begin=\"1s\" end=\"3s\">TTML fixture</span></p></div></body></tt>"]
        }
        let isLibrarySearch = self.request.url?.host == "lrclib.net" && self.request.url?.path == "/api/search"
        var status = Self.status
        var payload: Any = isLibrarySearch ? [body] : body as Any
        if Self.collaborationFixture {
            if isLibrarySearch {
                let query = URLComponents(url: self.request.url!, resolvingAgainstBaseURL: false)?.queryItems
                precondition(query?.contains(URLQueryItem(name: "artist_name", value: "bbno$")) == true)
                let metadata: [String: Any] = ["trackName": "1-800", "artistName": "bbno$", "instrumental": false]
                payload = [metadata.merging(["duration": 208.0, "plainLyrics": "plain"]){ _, new in new },
                    metadata.merging(["duration": 207.0, "syncedLyrics": "[00:01.00]synced"]){ _, new in new }]
            } else {
                status = 500
            }
        }
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let response = HTTPURLResponse(url: self.request.url!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: data)
        self.client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
private struct Regression {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsProtocol.self]
        NextgramLyricsHTTP.session = URLSession(configuration: configuration)
        let diskChild = CommandLine.arguments.count > 2 && CommandLine.arguments[1] == "--verify-disk"
        let title = diskChild ? CommandLine.arguments[2] : "Nextgram regression " + UUID().uuidString
        LyricsProtocol.title = title
        if diskChild {
            LyricsProtocol.status = 500
            guard case .found = await self.lookup(title), LyricsProtocol.count == 0 else { fatalError("Disk cache was not restored") }
            print("PASS: successful lyrics survive a new process without network")
            return
        }
        let key = "lrclib\u{1}\(title)\u{1}Singer A & Singer B\u{1}200"
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NextgramOnlineLyrics-v1").appendingPathComponent(name)
        defer {
            try? FileManager.default.removeItem(at: cache)
            for provider in ["netease", "kugou", "betterLyrics-2"] {
                let providerKey = key.replacingOccurrences(of: "lrclib\u{1}", with: provider + "\u{1}")
                let providerName = SHA256.hash(data: Data(providerKey.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
                try? FileManager.default.removeItem(at: cache.deletingLastPathComponent().appendingPathComponent(providerName))
            }
        }
        let initial = await self.lookup(title)
        guard case let .found(first) = initial, first.lines.count == 2 else {
            FileHandle.standardError.write(Data("Lookup: \(initial); requests: \(LyricsProtocol.count)\n".utf8))
            fatalError("Multi-artist match failed")
        }
        let count = LyricsProtocol.count
        guard case let .found(second) = await self.lookup(title), first == second, LyricsProtocol.count == count else { fatalError("Cache miss") }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--verify-disk", title]
        try child.run(); child.waitUntilExit()
        precondition(child.terminationStatus == 0)
        LyricsProtocol.status = 500
        let serviceError = await self.diagnostics(.lrclib, title: title)
        guard case .unavailable = serviceError.result, case .httpError(500)? = serviceError.events.last,
              LyricsProtocol.count > count else { fatalError("Refresh did not bypass cache or lost HTTP status") }
        guard case let .found(saved) = await self.lookup(title), saved == first else { fatalError("Failed refresh overwrote cache") }
        LyricsProtocol.networkFailure = true
        let networkError = await self.diagnostics(.lrclib, title: title)
        guard case .unavailable = networkError.result, case .networkError(-1009)? = networkError.events.last else { fatalError("Network error was not identified") }
        LyricsProtocol.networkFailure = false
        LyricsProtocol.status = 404
        guard case .noMatch = await self.lookup(title, refresh: true) else { fatalError("404 was not a no-match") }
        LyricsProtocol.status = 200
        LyricsProtocol.title = title + " (Live)"
        guard case .noMatch = await self.lookup(title, refresh: true) else { fatalError("Wrong recording matched") }
        LyricsProtocol.title = title
        LyricsProtocol.responseDuration = 210
        let mismatch = await self.diagnostics(.lrclib, title: title)
        guard case .noMatch = mismatch.result, mismatch.events.contains(where: {
            if case .candidate(_, _, 210, .durationMismatch) = $0 { return true }
            return false
        }) else { fatalError("Wrong duration matched or lost rejection reason") }
        precondition(NextgramOnlineLyrics.artistsMatch("Singer A feat. Singer B", foundArtists: ["Singer B", "Singer A"]))
        precondition(!NextgramOnlineLyrics.artistsMatch("Singer A & Someone Else", foundArtists: ["Singer A", "Singer B"]))
        precondition(!NextgramOnlineLyrics.artistsMatch("bbno$/Ironmouse", foundArtists: ["Ironmouse"]))
        LyricsProtocol.neteaseFixture = true
        let aliasResult = await NextgramOnlineLyrics.lookup(provider: .netease, title: title,
            artist: "Singer A & Singer B", duration: 200, forceRefresh: true)
        guard case let .found(aliasLyrics) = aliasResult, aliasLyrics.lines.count == 1 else { fatalError("NetEase song/artist alias resolution failed") }
        LyricsProtocol.neteaseFixture = false
        let kugou = await self.diagnostics(.kugou, title: title)
        guard case let .found(kugouLyrics) = kugou.result, kugouLyrics.lines.first?.text == "KuGou fixture", kugouLyrics.isSynced else {
            fatalError("KuGou LRC parsing failed")
        }
        let better = await self.diagnostics(.betterLyrics, title: title)
        guard case let .found(betterLyrics) = better.result, betterLyrics.lines.first?.words.count == 1 else {
            fatalError("Better Lyrics TTML word timings were not parsed")
        }
        let ttml = "<tt><body><div><p begin=\"1s\" end=\"3s\"><span begin=\"1s\" end=\"2s\">timed </span><span begin=\"2s\" end=\"3s\">words</span></p></div></body></tt>"
        let timed = NextgramLyrics.parse(ttml)!
        let restored = try JSONDecoder().decode(NextgramLyrics.self, from: JSONEncoder().encode(timed))
        precondition(timed == restored && restored.lines[0].words.count == 2)
        let translated = NextgramLyrics.parse("<tt xmlns:ttm=\"http://www.w3.org/ns/ttml#metadata\"><body><p begin=\"1s\"><span begin=\"1s\" end=\"2s\">Original</span><span ttm:role=\"x-translation\">翻译</span></p></body></tt>")!
        precondition(translated.lines[0].text == "Original" && translated.lines[0].translation == "翻译")
        precondition(translated.lookupQuality > timed.lookupQuality)
        LyricsProtocol.collaborationFixture = true
        let collaboration = await NextgramOnlineLyrics.lookup(provider: .lrclib, title: "1-800", artist: "bbno$/Ironmouse", duration: 208, forceRefresh: true)
        guard case let .found(lyrics) = collaboration, lyrics.isSynced, lyrics.lines[0].text == "synced" else {
            fatalError("Expected synchronized lyrics from fallback search for primary artist")
        }
        print("PASS: cache hit, forced retry, failure retention, 404/500 distinction, artist separators/order, version/duration rejection, word timing round-trip, NetEase title/artist alias resolution")
        print("PASS: network diagnostics, rejected candidate details, KuGou LRC and Better Lyrics TTML")
    }
    static func lookup(_ title: String, refresh: Bool = false) async -> NextgramLyricsLookupResult {
        await NextgramOnlineLyrics.lookup(provider: .lrclib, title: title, artist: "Singer A & Singer B", duration: 200, forceRefresh: refresh)
    }
    static func diagnostics(_ source: NextgramOnlineLyricsProvider, title: String) async -> (result: NextgramLyricsLookupResult, events: [NextgramLyricsLookupEvent]) {
        await NextgramOnlineLyrics.lookupWithDiagnostics(provider: source, title: title,
            artist: "Singer A & Singer B", duration: 200, forceRefresh: true)
    }
}
