import Foundation

public enum NextgramChatAliases {
    public static func all(accountPeerId: Int64) -> [String: String] {
        return NagramDemoMode.userDefaults.dictionary(forKey: self.key(accountPeerId: accountPeerId)) as? [String: String] ?? [:]
    }

    public static func name(accountPeerId: Int64, peerId: Int64) -> String? {
        return self.all(accountPeerId: accountPeerId)[String(peerId)]
    }

    public static func set(_ name: String, accountPeerId: Int64, peerId: Int64) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
        var names = self.all(accountPeerId: accountPeerId)
        names[String(peerId)] = trimmed.isEmpty ? nil : trimmed
        NagramDemoMode.userDefaults.set(names, forKey: self.key(accountPeerId: accountPeerId))
    }

    private static func key(accountPeerId: Int64) -> String {
        return "nextgram.chatAliases.\(accountPeerId)"
    }
}
