import Foundation

extension NextgramOnlineLyrics {
    private struct KuGouSearch: Decodable {
        struct Candidate: Decodable {
            let id: String
            let accesskey: String
            let song: String
            let singer: String
            let duration: Double
        }
        let status: Int
        let candidates: [Candidate]?
    }

    private struct KuGouLyrics: Decodable {
        let status: Int
        let content: String?
    }

    private struct BetterLyricsResponse: Decodable {
        let ttml: String?
    }

    static func kugou(title: String, artist: String, duration: Double, trace: LookupTrace) async throws -> NextgramLyrics? {
        let host = "lyrics.kugou.com"
        let data = try await NextgramLyricsHTTP.request(host: host, path: "/search", query: [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "man", value: "yes"),
            URLQueryItem(name: "keyword", value: artist + " - " + title),
            URLQueryItem(name: "duration", value: String(Int((duration * 1000).rounded())))
        ])
        let response = try JSONDecoder().decode(KuGouSearch.self, from: data)
        guard response.status == 200 else { throw URLError(.badServerResponse) }
        let candidates = (response.candidates ?? []).filter { candidate in
            matches(title: title, artist: artist, duration: duration, foundTitle: candidate.song,
                foundArtists: [candidate.singer], foundDuration: candidate.duration / 1000, trace: trace)
        }
        for candidate in candidates.prefix(2) {
            do {
                let data = try await NextgramLyricsHTTP.request(host: host, path: "/download", query: [
                    URLQueryItem(name: "ver", value: "1"), URLQueryItem(name: "client", value: "pc"),
                    URLQueryItem(name: "id", value: candidate.id), URLQueryItem(name: "accesskey", value: candidate.accesskey),
                    URLQueryItem(name: "fmt", value: "lrc"), URLQueryItem(name: "charset", value: "utf8")
                ])
                let response = try JSONDecoder().decode(KuGouLyrics.self, from: data)
                if response.status == 200, let content = response.content, let lyricsData = Data(base64Encoded: content),
                   let text = String(data: lyricsData, encoding: .utf8), let lyrics = NextgramLyrics.parse(text) {
                    return lyrics
                }
            } catch let error as NextgramLyricsHTTP.StatusError where error.code == 404 {
                continue
            }
        }
        return nil
    }

    static func betterLyrics(title: String, artist: String, duration: Double, trace: LookupTrace) async throws -> NextgramLyrics? {
        let data = try await NextgramLyricsHTTP.request(host: "api.betterlyrics.org", path: "/getLyrics", query: [
            URLQueryItem(name: "s", value: title), URLQueryItem(name: "a", value: artist),
            URLQueryItem(name: "d", value: String(Int(duration.rounded())))
        ])
        let response = try JSONDecoder().decode(BetterLyricsResponse.self, from: data)
        guard let text = response.ttml, let parsed = NextgramTTMLParser.parse(text) else { return nil }
        guard parsed.lastEnd <= duration + 3.0, parsed.duration.map({ abs($0 - duration) <= 5.0 }) != false else {
            trace(.timingMismatch)
            return nil
        }
        return parsed.lyrics
    }
}
