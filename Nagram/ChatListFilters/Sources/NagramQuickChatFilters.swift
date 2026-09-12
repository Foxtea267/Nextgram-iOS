import TelegramCore

public enum NagramChatListReadFilter: String {
    case all
    case unread
    case read

    fileprivate var encodedValue: Int32 {
        switch self {
        case .all:
            return 0
        case .unread:
            return 1
        case .read:
            return 2
        }
    }
}

public struct NagramChatListPeerTypes: OptionSet {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static let contacts = NagramChatListPeerTypes(rawValue: 1 << 0)
    public static let nonContacts = NagramChatListPeerTypes(rawValue: 1 << 1)
    public static let bots = NagramChatListPeerTypes(rawValue: 1 << 2)
    public static let groups = NagramChatListPeerTypes(rawValue: 1 << 3)
    public static let channels = NagramChatListPeerTypes(rawValue: 1 << 4)

    public static let privateChats: NagramChatListPeerTypes = [.contacts, .nonContacts, .bots]
    public static let strangers: NagramChatListPeerTypes = [.nonContacts, .bots]
    public static let all: NagramChatListPeerTypes = [.privateChats, .groups, .channels]
}

private let nagramCombinedChatFilterIdBase: Int32 = -1000

public func nagramCombinedChatListFilterId(readFilter: NagramChatListReadFilter, peerTypes: NagramChatListPeerTypes) -> Int32 {
    return nagramCombinedChatFilterIdBase - readFilter.encodedValue * 64 - peerTypes.rawValue
}

public func nagramCombinedChatListFilterReadMode(id: Int32) -> NagramChatListReadFilter? {
    let encodedValue = nagramCombinedChatFilterIdBase - id
    let peerTypes = encodedValue % 64
    guard peerTypes > 0, peerTypes & ~NagramChatListPeerTypes.all.rawValue == 0 else {
        return nil
    }
    switch encodedValue / 64 {
    case 0:
        return .all
    case 1:
        return .unread
    case 2:
        return .read
    default:
        return nil
    }
}

public func nagramIsCombinedChatListFilterId(_ id: Int32) -> Bool {
    return nagramCombinedChatListFilterReadMode(id: id) != nil
}

public func nagramCombinedChatListFilter(
    title: String,
    readFilter: NagramChatListReadFilter,
    peerTypes: NagramChatListPeerTypes
) -> ChatListFilter? {
    let peerTypes = peerTypes.intersection(.all)
    guard !peerTypes.isEmpty else {
        return nil
    }
    if readFilter == .all && peerTypes == .all {
        return nil
    }

    var categories: ChatListFilterPeerCategories = []
    if peerTypes.contains(.contacts) {
        categories.insert(.contacts)
    }
    if peerTypes.contains(.nonContacts) {
        categories.insert(.nonContacts)
    }
    if peerTypes.contains(.bots) {
        categories.insert(.bots)
    }
    if peerTypes.contains(.groups) {
        categories.insert(.groups)
    }
    if peerTypes.contains(.channels) {
        categories.insert(.channels)
    }

    return .filter(
        id: nagramCombinedChatListFilterId(readFilter: readFilter, peerTypes: peerTypes),
        title: ChatFolderTitle(text: title, entities: [], enableAnimations: false),
        emoticon: nil,
        data: ChatListFilterData(
            isShared: false,
            hasSharedLinks: false,
            categories: categories,
            excludeMuted: false,
            excludeRead: readFilter == .unread,
            excludeArchived: true,
            includePeers: ChatListFilterIncludePeers(),
            excludePeers: [],
            color: nil
        )
    )
}
