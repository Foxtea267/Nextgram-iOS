import Foundation

public enum NextgramChatDeletionPolicy: String, CaseIterable {
    case inherit
    case preserve
    case allow

    public static func current(accountId: Int64, chatId: Int64) -> Self {
        let value = NagramDemoMode.userDefaults.string(forKey: self.key(accountId: accountId, chatId: chatId))
        return value.flatMap(Self.init(rawValue:)) ?? .inherit
    }

    public func save(accountId: Int64, chatId: Int64) {
        let key = Self.key(accountId: accountId, chatId: chatId)
        if self == .inherit {
            NagramDemoMode.userDefaults.removeObject(forKey: key)
        } else {
            NagramDemoMode.userDefaults.set(self.rawValue, forKey: key)
        }
    }

    private static func key(accountId: Int64, chatId: Int64) -> String {
        return "nextgram.chatDeletionPolicy.\(accountId).\(chatId)"
    }
}
