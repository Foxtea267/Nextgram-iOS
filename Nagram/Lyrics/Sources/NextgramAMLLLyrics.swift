import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

final class NextgramTTMLParser: NSObject, XMLParserDelegate {
    private var depth = 0
    private var bodyDepth: Int?
    private var lineDepth: Int?
    private var ignoredDepth: Int?
    private var lineStart = 0.0
    private var lineEnd = 0.0
    private var lineText = ""
    private var words: [NextgramLyricWord] = []
    private var word: (depth: Int, time: Double, end: Double, offset: Int)?
    private var lines: [NextgramLyricLine] = []
    private var rootIsTTML = false
    private var duration: Double?
    private var lastEnd = 0.0

    static func parse(_ text: String) -> (lyrics: NextgramLyrics, duration: Double?, lastEnd: Double)? {
        guard text.utf8.count <= NextgramLyrics.maximumFileSize,
              !text.contains("<!DOCTYPE"), !text.contains("<!ENTITY") else { return nil }
        let delegate = Self()
        let parser = XMLParser(data: Data(text.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.rootIsTTML, !delegate.lines.isEmpty else { return nil }
        let lines = delegate.lines.enumerated().sorted { lhs, rhs in
            let a = lhs.element.time ?? 0.0, b = rhs.element.time ?? 0.0
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
        return (NextgramLyrics(lines: lines, isSynced: true), delegate.duration, delegate.lastEnd)
    }

    private static func timestamp(_ input: String?) -> Double? {
        guard let input else { return nil }
        let value: Double
        if input.hasSuffix("ms"), let number = Double(input.dropLast(2)) {
            value = number / 1000.0
        } else if input.hasSuffix("s"), let number = Double(input.dropLast()) {
            value = number
        } else {
            let fields = input.split(separator: ":", omittingEmptySubsequences: false)
            guard (1 ... 3).contains(fields.count) else { return nil }
            var time = 0.0
            for field in fields {
                guard let part = Double(field), part.isFinite, part >= 0.0 else { return nil }
                time = time * 60.0 + part
            }
            value = time
        }
        return value.isFinite && value >= 0.0 && value < 360000.0 ? value : nil
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        self.depth += 1
        guard self.depth <= 48 else { parser.abortParsing(); return }
        let local = element.split(separator: ":").last
        if self.depth == 1 { self.rootIsTTML = local == "tt" }
        if local == "body" {
            self.bodyDepth = self.depth
            self.duration = Self.timestamp(attributes["dur"])
        }
        guard self.bodyDepth != nil, self.ignoredDepth == nil else { return }
        if local == "p", self.lineDepth == nil, let start = Self.timestamp(attributes["begin"]) {
            self.lineDepth = self.depth
            self.lineStart = start
            self.lineEnd = max(start, Self.timestamp(attributes["end"]) ?? start)
            self.lineText = ""
            self.words = []
        } else if self.lineDepth != nil && local == "span" {
            let role = attributes["ttm:role"]
            if role == "x-bg" || role == "x-translation" || role == "x-roman" {
                self.ignoredDepth = self.depth
            } else if self.word == nil, let start = Self.timestamp(attributes["begin"]),
                      let end = Self.timestamp(attributes["end"]), end >= start {
                self.word = (self.depth, start, end, self.lineText.utf16.count)
            }
        } else if self.lineDepth != nil && local == "br" {
            self.lineText.append("\n")
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard self.lineDepth != nil, self.ignoredDepth == nil else { return }
        if string.contains("\n") && string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        self.lineText.append(string)
        if self.lineText.utf8.count > 16000 { parser.abortParsing() }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        defer { self.depth -= 1 }
        if self.ignoredDepth == self.depth {
            self.ignoredDepth = nil
            return
        }
        if let word = self.word, word.depth == self.depth {
            self.word = nil
            let length = self.lineText.utf16.count - word.offset
            if length > 0 {
                self.words.append(NextgramLyricWord(time: word.time, end: word.end,
                    range: NSRange(location: word.offset, length: length)))
                self.lineEnd = max(self.lineEnd, word.end)
            }
        }
        if self.lineDepth == self.depth {
            self.lineDepth = nil
            if !self.lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.lastEnd = max(self.lastEnd, self.lineEnd)
                self.lines.append(NextgramLyricLine(time: self.lineStart, text: self.lineText, words: self.words))
                if self.lines.count > 10000 { parser.abortParsing() }
            }
        }
        if self.bodyDepth == self.depth { self.bodyDepth = nil }
    }
}

public enum NextgramAMLLLyrics {
    private struct Response<Item: Decodable>: Decodable {
        let status: Int
        let data: Item
    }

    private struct Song: Decodable {
        let id: Int64
        let musicNames: [String]
        let artistNames: [String]
        let lyrics: String?
    }

    private struct Search: Decodable {
        let items: [Song]
    }

    public static func fetch(title: String, artist: String, duration: Double) async -> NextgramLyrics? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleKey = self.normalized(title)
        let artistKey = self.normalized(artist)
        guard !titleKey.isEmpty, !artistKey.isEmpty, title.utf8.count <= 512, artist.utf8.count <= 512,
              duration.isFinite, duration > 0.0 else { return nil }
        do {
            let search: Search = try await self.request(path: "search", query: [
                URLQueryItem(name: "musicName", value: title), URLQueryItem(name: "artistName", value: artist),
                URLQueryItem(name: "pageSize", value: "8")
            ])
            func matches(_ song: Song) -> Bool {
                song.musicNames.contains { self.normalized($0) == titleKey } &&
                (song.artistNames.contains { self.normalized($0) == artistKey } ||
                    self.normalized(song.artistNames.joined(separator: " ")) == artistKey)
            }
            for item in search.items.filter(matches).prefix(2) {
                try Task.checkCancellation()
                let song: Song = try await self.request(path: "get", query: [URLQueryItem(name: "id", value: String(item.id))])
                guard song.id == item.id, matches(song), let text = song.lyrics,
                      let parsed = NextgramTTMLParser.parse(text), parsed.lastEnd <= duration + 3.0 else { continue }
                if let listedDuration = parsed.duration, abs(listedDuration - duration) > 5.0 { continue }
                return parsed.lyrics
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func request<Item: Decodable>(path: String, query: [URLQueryItem]) async throws -> Item {
        let data = try await NextgramLyricsHTTP.request(host: "api.amll.dev", path: "/v1/lyrics/" + path, query: query)
        let decoded = try JSONDecoder().decode(Response<Item>.self, from: data)
        guard decoded.status == 200 else { throw URLError(.badServerResponse) }
        return decoded.data
    }

    private static func normalized(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
