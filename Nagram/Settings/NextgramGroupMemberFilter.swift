import Foundation

public enum NextgramGroupMemberFilter {
    public static func hiddenMembers(accountId: Int64, chatId: Int64) -> Set<Int64> {
        let values = NagramDemoMode.userDefaults.string(forKey: self.key(accountId: accountId, chatId: chatId)) ?? ""
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
            NagramDemoMode.userDefaults.removeObject(forKey: key)
        } else {
            NagramDemoMode.userDefaults.set(members.sorted().map { String($0) }.joined(separator: ","), forKey: key)
        }
    }

    public static func key(accountId: Int64, chatId: Int64) -> String {
        return "nextgram.hiddenGroupMembers.\(accountId).\(chatId)"
    }

    private static func parse(_ value: String) -> Set<Int64> {
        return Set(value.split(separator: ",").compactMap { Int64($0) })
    }
}
