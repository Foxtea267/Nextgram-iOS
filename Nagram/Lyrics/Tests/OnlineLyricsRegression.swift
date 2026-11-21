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

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.count += 1
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
        let data = try! JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(url: self.request.url!, statusCode: Self.status,
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
            let neteaseKey = key.replacingOccurrences(of: "lrclib\u{1}", with: "netease\u{1}")
            let neteaseName = SHA256.hash(data: Data(neteaseKey.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
            try? FileManager.default.removeItem(at: cache.deletingLastPathComponent().appendingPathComponent(neteaseName))
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
        guard case .unavailable = await self.lookup(title, refresh: true), LyricsProtocol.count > count else { fatalError("Refresh did not bypass cache or lost error") }
        guard case let .found(saved) = await self.lookup(title), saved == first else { fatalError("Failed refresh overwrote cache") }
        LyricsProtocol.status = 404
        guard case .noMatch = await self.lookup(title, refresh: true) else { fatalError("404 was not a no-match") }
        LyricsProtocol.status = 200
        LyricsProtocol.title = title + " (Live)"
        guard case .noMatch = await self.lookup(title, refresh: true) else { fatalError("Wrong recording matched") }
        LyricsProtocol.title = title
        LyricsProtocol.responseDuration = 210
        guard case .noMatch = await self.lookup(title, refresh: true) else { fatalError("Wrong duration matched") }
        precondition(NextgramOnlineLyrics.artistsMatch("Singer A feat. Singer B", foundArtists: ["Singer B", "Singer A"]))
        precondition(!NextgramOnlineLyrics.artistsMatch("Singer A & Someone Else", foundArtists: ["Singer A", "Singer B"]))
        LyricsProtocol.neteaseFixture = true
        let aliasResult = await NextgramOnlineLyrics.lookup(provider: .netease, title: title,
            artist: "Singer A & Singer B", duration: 200, forceRefresh: true)
        guard case let .found(aliasLyrics) = aliasResult, aliasLyrics.lines.count == 1 else { fatalError("NetEase song/artist alias resolution failed") }
        LyricsProtocol.neteaseFixture = false
        let ttml = "<tt><body><div><p begin=\"1s\" end=\"3s\"><span begin=\"1s\" end=\"2s\">timed </span><span begin=\"2s\" end=\"3s\">words</span></p></div></body></tt>"
        let timed = NextgramLyrics.parse(ttml)!
        let restored = try JSONDecoder().decode(NextgramLyrics.self, from: JSONEncoder().encode(timed))
        precondition(timed == restored && restored.lines[0].words.count == 2)
        print("PASS: cache hit, forced retry, failure retention, 404/500 distinction, artist separators/order, version/duration rejection, word timing round-trip, NetEase title/artist alias resolution")
    }
    static func lookup(_ title: String, refresh: Bool = false) async -> NextgramLyricsLookupResult {
        await NextgramOnlineLyrics.lookup(provider: .lrclib, title: title, artist: "Singer A & Singer B", duration: 200, forceRefresh: refresh)
    }
}
