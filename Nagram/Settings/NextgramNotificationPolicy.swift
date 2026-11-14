import Foundation

public enum NextgramNotificationMode: String, CaseIterable {
    case `default`, silent, off
}

public enum NextgramNotificationPolicy {
    private static let sharedDefaults: UserDefaults? = {
        guard !NagramDemoMode.isEnabled, let identifier = Bundle.main.bundleIdentifier else { return nil }
        let suffix = ".NotificationService"
        return UserDefaults(suiteName: "group." + (identifier.hasSuffix(suffix) ? String(identifier.dropLast(suffix.count)) : identifier))
    }()

    private static let defaults: UserDefaults = {
        let local = NagramDemoMode.userDefaults
        if Bundle.main.bundleIdentifier?.hasSuffix(".NotificationService") == true { return NextgramNotificationPolicy.sharedDefaults ?? local }
        for category in ["pin", "mention", "reply"] {
            let key = "nextgram.notificationPolicy." + category
            NextgramNotificationPolicy.sharedDefaults?.set(local.object(forKey: key), forKey: key)
        }
        return local
    }()

    public static func mode(for category: String) -> NextgramNotificationMode {
        return NextgramNotificationMode(rawValue: self.defaults.string(forKey: "nextgram.notificationPolicy." + category) ?? "") ?? .default
    }

    public static func setMode(_ mode: NextgramNotificationMode, for category: String) {
        guard ["pin", "mention", "reply"].contains(category) else { return }
        let key = "nextgram.notificationPolicy." + category
        self.defaults.set(mode.rawValue, forKey: key)
        self.sharedDefaults?.set(mode.rawValue, forKey: key)
    }
}
