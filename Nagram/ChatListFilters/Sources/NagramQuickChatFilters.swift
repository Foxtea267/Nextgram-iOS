import TelegramCore

public enum NagramQuickChatFilter: Int32, CaseIterable {
    case contacts = -101
    case nonContacts = -106
    case privateChats = -102
    case groups = -103
    case channels = -104
    case groupsAndChannels = -107
    case unread = -105
    case read = -108

    public var titleKey: String {
        switch self {
        case .contacts:
            return "Nagram.ChatListQuickFilter.Contacts"
        case .privateChats:
            return "Nagram.ChatListQuickFilter.Private"
        case .groups:
            return "Nagram.ChatListQuickFilter.Groups"
        case .channels:
            return "Nagram.ChatListQuickFilter.Channels"
        case .unread:
            return "Nagram.ChatListQuickFilter.Unread"
        case .nonContacts:
            return "Nagram.ChatListQuickFilter.NonContacts"
        case .groupsAndChannels:
            return "Nagram.ChatListQuickFilter.GroupsAndChannels"
        case .read:
            return "Nagram.ChatListQuickFilter.Read"
        }
    }

    public var icon: String {
        switch self {
        case .contacts:
            return "👤"
        case .privateChats:
            return "💬"
        case .groups:
            return "👥"
        case .channels:
            return "📣"
        case .unread:
            return "🔵"
        case .nonContacts:
            return "👤"
        case .groupsAndChannels:
            return "📢"
        case .read:
            return "✅"
        }
    }
}

public func nagramQuickChatListFilters(title: (String) -> String) -> [ChatListFilter] {
    return NagramQuickChatFilter.allCases.map { kind in
        let categories: ChatListFilterPeerCategories
        let excludeRead: Bool
        switch kind {
        case .contacts:
            categories = [.contacts]
            excludeRead = false
        case .privateChats:
            categories = [.contacts, .nonContacts, .bots]
            excludeRead = false
        case .groups:
            categories = [.groups]
            excludeRead = false
        case .channels:
            categories = [.channels]
            excludeRead = false
        case .unread:
            categories = .all
            excludeRead = true
        case .nonContacts:
            categories = [.nonContacts]
            excludeRead = false
        case .groupsAndChannels:
            categories = [.groups, .channels]
            excludeRead = false
        case .read:
            // Telegram folders only support excluding read chats. The read-only
            // half of this local filter is applied by ChatListNodeEntries.
            categories = .all
            excludeRead = false
        }
        return .filter(
            id: kind.rawValue,
            title: ChatFolderTitle(text: title(kind.titleKey), entities: [], enableAnimations: false),
            emoticon: kind.icon,
            data: ChatListFilterData(
                isShared: false,
                hasSharedLinks: false,
                categories: categories,
                excludeMuted: false,
                excludeRead: excludeRead,
                excludeArchived: true,
                includePeers: ChatListFilterIncludePeers(),
                excludePeers: [],
                color: nil
            )
        )
    }
}
