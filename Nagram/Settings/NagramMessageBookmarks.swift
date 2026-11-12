import Foundation

public struct NagramBookmarkLocation: Codable, Hashable, Sendable {
    public let peerId: Int64
    public let namespace: Int32
    public let messageId: Int32

    public init(peerId: Int64, namespace: Int32, messageId: Int32) {
        self.peerId = peerId
        self.namespace = namespace
        self.messageId = messageId
    }
}

public struct NagramMessageBookmark: Codable, Equatable, Sendable {
    public let location: NagramBookmarkLocation
    public let threadId: Int64?
    public let date: Date
    public let tags: [String]
}

public enum NagramMessageBookmarks {
    private static let lock = NSLock()

    public static func list(accountId: Int64) throws -> [NagramMessageBookmark] {
        lock.lock()
        defer { lock.unlock() }
        return try read(accountId: accountId)
    }

    public static func save(accountId: Int64, location: NagramBookmarkLocation, threadId: Int64?, tags: [String]) throws {
        lock.lock()
        defer { lock.unlock() }
        var bookmarks = try read(accountId: accountId)
        let index = bookmarks.firstIndex { $0.location == location }
        let date = index.map { bookmarks[$0].date } ?? Date()
        var tagKeys = Set<String>()
        let normalized = tags.compactMap { value -> String? in
            let tag = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            return !tag.isEmpty && tagKeys.insert(tag.lowercased()).inserted ? tag : nil
        }
        let bookmark = NagramMessageBookmark(location: location, threadId: threadId, date: date, tags: Array(normalized.prefix(12)))
        if let index {
            bookmarks[index] = bookmark
        } else {
            bookmarks.insert(bookmark, at: 0)
        }
        try write(bookmarks, accountId: accountId)
    }

    public static func remove(accountId: Int64, location: NagramBookmarkLocation) throws {
        lock.lock()
        defer { lock.unlock() }
        var bookmarks = try read(accountId: accountId)
        bookmarks.removeAll { $0.location == location }
        try write(bookmarks, accountId: accountId)
    }

    private static func key(accountId: Int64) -> String {
        return "nextgram.messageBookmarks.\(accountId)"
    }

    private static func read(accountId: Int64) throws -> [NagramMessageBookmark] {
        guard let data = NagramDemoMode.userDefaults.data(forKey: key(accountId: accountId)) else {
            return []
        }
        return try JSONDecoder().decode([NagramMessageBookmark].self, from: data)
    }

    private static func write(_ bookmarks: [NagramMessageBookmark], accountId: Int64) throws {
        let data = try JSONEncoder().encode(bookmarks)
        NagramDemoMode.userDefaults.set(data, forKey: key(accountId: accountId))
    }
}
