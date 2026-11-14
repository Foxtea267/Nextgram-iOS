import Foundation

/// Local, per-account/per-group opt-in. Does not change Telegram's server notification settings.
public enum NextgramMemberNotifications {
    private static let sharedDefaults: UserDefaults? = {
        guard !NagramDemoMode.isEnabled, let identifier = Bundle.main.bundleIdentifier else { return nil }
        let suffix = ".NotificationService"
        let appIdentifier = identifier.hasSuffix(suffix) ? String(identifier.dropLast(suffix.count)) : identifier
        return UserDefaults(suiteName: "group.\(appIdentifier)")
    }()
    private static let defaults: UserDefaults = {
        let local = NagramDemoMode.userDefaults
        if Bundle.main.bundleIdentifier?.hasSuffix(".NotificationService") == true { return NextgramMemberNotifications.sharedDefaults ?? local }
        for (key, value) in local.dictionaryRepresentation() where key.hasPrefix("nextgram.memberNotifications.") {
            NextgramMemberNotifications.sharedDefaults?.set(value, forKey: key)
        }
        return local
    }()

    public static func key(accountId: Int64, chatId: Int64) -> String {
        return "nextgram.memberNotifications.\(accountId).\(chatId)"
    }

    public static func members(accountId: Int64, chatId: Int64) -> Set<Int64> {
        return Set((self.defaults.string(forKey: self.key(accountId: accountId, chatId: chatId)) ?? "")
            .split(separator: ",").compactMap { Int64($0) })
    }

    public static func chats(accountId: Int64) -> [Int64] {
        let prefix = "nextgram.memberNotifications.\(accountId)."
        return self.defaults.dictionaryRepresentation().keys.compactMap { key in
            guard key.hasPrefix(prefix), let chatId = Int64(key.dropFirst(prefix.count)),
                  !self.members(accountId: accountId, chatId: chatId).isEmpty else { return nil }
            return chatId
        }.sorted()
    }

    public static func setEnabled(_ enabled: Bool, memberId: Int64, accountId: Int64, chatId: Int64) {
        var members = self.members(accountId: accountId, chatId: chatId)
        if enabled { members.insert(memberId) } else { members.remove(memberId) }
        let key = self.key(accountId: accountId, chatId: chatId)
        if members.isEmpty {
            self.defaults.removeObject(forKey: key)
            self.sharedDefaults?.removeObject(forKey: key)
        } else {
            let value = members.sorted().map { String($0) }.joined(separator: ",")
            self.defaults.set(value, forKey: key)
            self.sharedDefaults?.set(value, forKey: key)
        }
        self.defaults.set(UUID().uuidString, forKey: "nextgram.memberNotificationsRevision.\(accountId)")
    }

    public static func isEligible(selected: Bool, isGroup: Bool, incoming: Bool, imported: Bool, unread: Bool, serviceMessage: Bool = false) -> Bool {
        return selected && isGroup && incoming && !imported && unread && !serviceMessage
    }
}
