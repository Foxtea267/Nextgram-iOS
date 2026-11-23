import Foundation
import ImageIO
import UIKit

actor NextgramOnlineArtwork {
    static let shared = NextgramOnlineArtwork()

    private struct SearchResult: Decodable {
        let recordings: [Recording]
    }

    private struct Recording: Decodable {
        struct Credit: Decodable {
            let name: String
            let joinphrase: String?
        }
        struct Release: Decodable {
            let id: UUID
            let status: String?
        }
        let title: String
        let length: Int?
        let artistCredit: [Credit]?
        let releases: [Release]?

        enum CodingKeys: String, CodingKey {
            case title, length, releases
            case artistCredit = "artist-credit"
        }
    }

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8.0
        configuration.timeoutIntervalForResource = 12.0
        return URLSession(configuration: configuration)
    }()
    private var lastSearch = 0.0

    init() {
        self.cache.countLimit = 24
        self.cache.totalCostLimit = 48 * 1024 * 1024
    }

    func artwork(title: String, artist: String, duration: Double) async -> UIImage? {
        let titleKey = Self.normalized(title)
        let artistKey = Self.normalized(artist)
        guard !titleKey.isEmpty, !artistKey.isEmpty else { return nil }
        let seconds = duration.isFinite && duration > 0 && duration < 86400 ? Int(duration.rounded()) : 0
        let key = "\(titleKey)\u{0}\(artistKey)\u{0}\(seconds)" as NSString
        if let image = self.cache.object(forKey: key) { return image }

        var url = URLComponents(string: "https://musicbrainz.org/ws/2/recording")!
        url.queryItems = [
            URLQueryItem(name: "query", value: "recording:\"\(Self.escaped(title))\" AND artist:\"\(Self.escaped(artist))\""),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "25")
        ]
        guard let address = url.url else { return nil }
        do {
            while self.lastSearch + 1.1 > ProcessInfo.processInfo.systemUptime {
                let delay = self.lastSearch + 1.1 - ProcessInfo.processInfo.systemUptime
                try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            }
            try Task.checkCancellation()
            self.lastSearch = ProcessInfo.processInfo.systemUptime
            var request = URLRequest(url: address)
            request.setValue("Nextgram/1.0 (https://github.com/Foxtea267/Nextgram-iOS)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await self.session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let results = try JSONDecoder().decode(SearchResult.self, from: data)
            var seen = Set<UUID>()
            var releases: [Recording.Release] = []
            for recording in results.recordings {
                let credits = recording.artistCredit ?? []
                let creditedArtist = credits.map { $0.name + ($0.joinphrase ?? "") }.joined()
                guard Self.normalized(recording.title) == titleKey, Self.normalized(creditedArtist) == artistKey else { continue }
                if seconds > 0, let length = recording.length, abs(Double(length) / 1000.0 - duration) > 8.0 { continue }
                for release in recording.releases ?? [] where seen.insert(release.id).inserted {
                    releases.append(release)
                }
            }
            let preferredReleases = releases.filter { $0.status == "Official" } + releases.filter { $0.status != "Official" }
            for release in preferredReleases.prefix(3) {
                for size in [1200, 500] {
                    try Task.checkCancellation()
                    let address = URL(string: "https://coverartarchive.org/release/\(release.id.uuidString.lowercased())/front-\(size)")!
                    guard let (bytes, response) = try? await self.session.data(from: address),
                          (response as? HTTPURLResponse)?.statusCode == 200,
                          bytes.count <= 8 * 1024 * 1024,
                          let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                          let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 1200
                          ] as CFDictionary) else { continue }
                    try Task.checkCancellation()
                    let image = UIImage(cgImage: bitmap)
                    self.cache.setObject(image, forKey: key, cost: bitmap.bytesPerRow * bitmap.height)
                    return image
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func normalized(_ text: String) -> String {
        return text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    private static func escaped(_ text: String) -> String {
        return String(text.prefix(160)).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
