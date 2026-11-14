import Foundation

public enum NextgramGroupMemberFilter {
    private static let sharedDefaults: UserDefaults? = {
        guard !NagramDemoMode.isEnabled, let identifier = Bundle.main.bundleIdentifier else {
            return nil
        }
        let suffix = ".NotificationService"
        let appIdentifier = identifier.hasSuffix(suffix) ? String(identifier.dropLast(suffix.count)) : identifier
        return UserDefaults(suiteName: "group.\(appIdentifier)")
    }()

    private static let defaults: UserDefaults = {
        let local = NagramDemoMode.userDefaults
        if Bundle.main.bundleIdentifier?.hasSuffix(".NotificationService") == true {
            return NextgramGroupMemberFilter.sharedDefaults ?? local
        }
        // Migrate existing lists too, before the next notification extension launch.
        if let shared = NextgramGroupMemberFilter.sharedDefaults {
            for (key, value) in local.dictionaryRepresentation() where key.hasPrefix("nextgram.hiddenGroupMembers.") {
                shared.set(value, forKey: key)
            }
        }
        return local
    }()

    public static func revisionKey(accountId: Int64) -> String {
        return "nextgram.hiddenGroupMembersRevision.\(accountId)"
    }

    public static func hiddenMembers(accountId: Int64, chatId: Int64) -> Set<Int64> {
        let values = self.defaults.string(forKey: self.key(accountId: accountId, chatId: chatId)) ?? ""
        return self.parse(values)
    }

    public static func setHidden(_ hidden: Bool, memberId: Int64, accountId: Int64, chatId: Int64) {
        var members = self.hiddenMembers(accountId: accountId, chatId: chatId)
        if hidden {
            members.insert(memberId)
        } else {
            members.remove(memberId)
        }
        let key = self.key(accountId: accountId, chatId: chatId)
        if members.isEmpty {
            self.defaults.removeObject(forKey: key)
            self.sharedDefaults?.removeObject(forKey: key)
        } else {
            let value = members.sorted().map { String($0) }.joined(separator: ",")
            self.defaults.set(value, forKey: key)
            self.sharedDefaults?.set(value, forKey: key)
        }
        NagramDemoMode.userDefaults.set(UUID().uuidString, forKey: self.revisionKey(accountId: accountId))
    }

    public static func key(accountId: Int64, chatId: Int64) -> String {
        return "nextgram.hiddenGroupMembers.\(accountId).\(chatId)"
    }

    private static func parse(_ value: String) -> Set<Int64> {
        return Set(value.split(separator: ",").compactMap { Int64($0) })
    }
}
