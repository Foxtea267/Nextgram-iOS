import Foundation

public struct NextgramChannelFeedPreferences: Codable, Equatable {
    public struct Category: Codable, Equatable {
        public let id: UUID
        public var name: String
        public var channelIds: Set<Int64>

        public init(name: String, channelIds: Set<Int64>) {
            self.id = UUID()
            self.name = name
            self.channelIds = channelIds
        }
    }

    public var excludedChannelIds: Set<Int64> = []
    public var manuallyIncludedChannelIds: Set<Int64>?
    public var categories: [Category] = []
    public var selectedCategoryId: UUID?
    public var unreadOnly = false

    public func includesInDefaultFeed(channelId: Int64) -> Bool {
        return self.manuallyIncludedChannelIds?.contains(channelId) ?? !self.excludedChannelIds.contains(channelId)
    }

    public mutating func setAutomaticallyIncludesNewChannels(_ enabled: Bool, knownChannelIds: Set<Int64>) {
        if enabled {
            guard let manual = self.manuallyIncludedChannelIds else { return }
            self.excludedChannelIds.formUnion(knownChannelIds.subtracting(manual))
            self.excludedChannelIds.subtract(manual)
            self.manuallyIncludedChannelIds = nil
        } else if self.manuallyIncludedChannelIds == nil {
            self.manuallyIncludedChannelIds = knownChannelIds.subtracting(self.excludedChannelIds)
        }
    }

    public static func load(accountId: Int64) -> Self {
        guard let data = NagramDemoMode.userDefaults.data(forKey: self.key(accountId: accountId)),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self()
        }
        return value
    }

    public func save(accountId: Int64) {
        if let data = try? JSONEncoder().encode(self) {
            NagramDemoMode.userDefaults.set(data, forKey: Self.key(accountId: accountId))
        }
    }

    private static func key(accountId: Int64) -> String {
        return "nextgram.channelFeed.\(accountId)"
    }
}
