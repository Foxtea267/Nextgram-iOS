import Foundation

public extension Notification.Name {
    static let nagramRecentChatsDidChange = Notification.Name("NagramRecentChatsDidChange")
    static let nagramRecentChatFolderSettingsDidChange = Notification.Name("NagramRecentChatFolderSettingsDidChange")
}

// MARK: NAGRAM — 最近会话存储。字符串落盘,由 UI 侧负责 PeerId 往返。
public extension NagramSettings {
    private var recentChatsLimit: Int {
        return 50
    }

    private func recentChatsKey(accountPeerId: Int64) -> String {
        return "nagram.recentChats.\(accountPeerId)"
    }
    
    private func recentChatFoldersKey(accountPeerId: Int64) -> String {
        return "nagram.recentChatFolders.\(accountPeerId)"
    }

    func recentChatIds(accountPeerId: Int64, limit: Int? = nil) -> [Int64] {
        let values = UserDefaults.standard.stringArray(forKey: self.recentChatsKey(accountPeerId: accountPeerId))?.compactMap(Int64.init) ?? []
        if let limit {
            return Array(values.prefix(limit))
        } else {
            return values
        }
    }
    
    func isRecentChatFolderEnabled(accountPeerId: Int64, filterId: Int32) -> Bool {
        guard filterId > 0 else {
            return false
        }
        return UserDefaults.standard.stringArray(forKey: self.recentChatFoldersKey(accountPeerId: accountPeerId))?.contains(String(filterId)) ?? false
    }
    
    func hasRecentChatFolderEnabled(accountPeerId: Int64) -> Bool {
        return !(UserDefaults.standard.stringArray(forKey: self.recentChatFoldersKey(accountPeerId: accountPeerId)) ?? []).isEmpty
    }
    
    func setRecentChatFolderEnabled(_ enabled: Bool, accountPeerId: Int64, filterId: Int32) {
        guard filterId > 0 else {
            return
        }
        
        let key = self.recentChatFoldersKey(accountPeerId: accountPeerId)
        var values = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let id = String(filterId)
        let hadValue = values.contains(id)
        if enabled {
            values.insert(id)
        } else {
            values.remove(id)
        }
        if values.isEmpty {
            NagramSettingsCloudSync.shared.removeObject(forKey: key)
        } else {
            NagramSettingsCloudSync.shared.set(Array(values).sorted(), forKey: key)
        }
        
        if hadValue != enabled {
            NotificationCenter.default.post(
                name: .nagramRecentChatFolderSettingsDidChange,
                object: self,
                userInfo: ["accountPeerId": accountPeerId, "filterId": filterId]
            )
        }
    }

    func addRecentChatId(_ peerId: Int64, accountPeerId: Int64) {
        guard self.recentChatsEnabled || self.hasRecentChatFolderEnabled(accountPeerId: accountPeerId) else {
            return
        }
        var values = self.recentChatIds(accountPeerId: accountPeerId)
        if values.first == peerId {
            return
        }
        values.removeAll(where: { $0 == peerId })
        values.insert(peerId, at: 0)
        if values.count > self.recentChatsLimit {
            values.removeSubrange(self.recentChatsLimit ..< values.count)
        }
        UserDefaults.standard.set(values.map { String($0) }, forKey: self.recentChatsKey(accountPeerId: accountPeerId))
        NotificationCenter.default.post(
            name: .nagramRecentChatsDidChange,
            object: self,
            userInfo: ["accountPeerId": accountPeerId]
        )
    }
    
    func removeRecentChatId(_ peerId: Int64, accountPeerId: Int64) {
        var values = self.recentChatIds(accountPeerId: accountPeerId)
        let previousCount = values.count
        values.removeAll(where: { $0 == peerId })
        guard values.count != previousCount else {
            return
        }
        
        let key = self.recentChatsKey(accountPeerId: accountPeerId)
        if values.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(values.map { String($0) }, forKey: key)
        }
        NotificationCenter.default.post(
            name: .nagramRecentChatsDidChange,
            object: self,
            userInfo: ["accountPeerId": accountPeerId]
        )
    }
}
