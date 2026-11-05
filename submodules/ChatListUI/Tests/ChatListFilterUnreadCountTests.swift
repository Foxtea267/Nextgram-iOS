import XCTest
import Postbox
import TelegramCore
@testable import ChatListUI

// MARK: NAGRAM — 分组标签的未读数：分组内置顶的聊天只计一次。
final class ChatListFilterUnreadCountTests: XCTestCase {
    private typealias PeerUnreadState = (EnginePeerSummaryCounterTags, Int, Bool, EnginePeerGroupId?, Bool)

    private func peerId(_ namespace: PeerId.Namespace, _ id: Int64) -> PeerId {
        return PeerId(namespace: namespace, id: PeerId.Id._internalFromInt64Value(id))
    }

    private func folder(_ includePeers: ChatListFilterIncludePeers) -> ChatListFilterData {
        return ChatListFilterData(
            isShared: false,
            hasSharedLinks: false,
            categories: [],
            excludeMuted: false,
            excludeRead: false,
            excludeArchived: false,
            includePeers: includePeers,
            excludePeers: [],
            color: nil
        )
    }

    // One unmuted unread message in a chat that lives in the root chat list.
    private func unread(_ tag: EnginePeerSummaryCounterTags) -> PeerUnreadState {
        return (tag, 1, true, .root, false)
    }

    private func count(_ data: ChatListFilterData, _ peerTagAndCount: [PeerId: PeerUnreadState], secretChatsByUserId: [PeerId: [PeerId]] = [:]) -> (count: Int, hasUnmuted: Bool) {
        return chatListFilterUnreadCount(data: data, totalStates: [:], peerTagAndCount: peerTagAndCount, secretChatsByUserId: secretChatsByUserId)
    }

    // Pinning a chat inside a folder lists it in both `peers` and `pinnedPeers`; the badge showed 2.
    func testPinnedGroupIsCountedOnce() {
        let groupId = peerId(Namespaces.Peer.CloudGroup, 1)
        var includePeers = ChatListFilterIncludePeers()
        XCTAssertTrue(includePeers.addPinnedPeer(groupId))
        XCTAssertEqual(includePeers.peers, [groupId])
        XCTAssertEqual(includePeers.pinnedPeers, [groupId])

        let result = count(folder(includePeers), [groupId: unread(.group)])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.hasUnmuted)
    }

    // Seven unread groups, all pinned in the folder, next to read members: the badge showed 14.
    func testSevenPinnedGroupsAreCountedOnceEach() {
        var includePeers = ChatListFilterIncludePeers()
        var peerTagAndCount: [PeerId: PeerUnreadState] = [:]
        for id in 1 ... 7 {
            let groupId = peerId(Namespaces.Peer.CloudChannel, Int64(id))
            XCTAssertTrue(includePeers.addPinnedPeer(groupId))
            peerTagAndCount[groupId] = unread(.group)
        }
        for id in 8 ... 10 {
            XCTAssertTrue(includePeers.addPeer(peerId(Namespaces.Peer.CloudChannel, Int64(id))))
        }

        XCTAssertEqual(count(folder(includePeers), peerTagAndCount).count, 7)
    }

    // Secret chats in a folder stay counted: one carried by an included user, and one pinned on its
    // own, which ChatListFilterIncludePeers keeps out of `peers`.
    func testSecretChatsAreCountedOnce() {
        let userId = peerId(Namespaces.Peer.CloudUser, 1)
        let carriedSecretChatId = peerId(Namespaces.Peer.SecretChat, 1)
        let pinnedSecretChatId = peerId(Namespaces.Peer.SecretChat, 2)

        var includePeers = ChatListFilterIncludePeers()
        XCTAssertTrue(includePeers.addPinnedPeer(userId))
        XCTAssertTrue(includePeers.addPinnedPeer(pinnedSecretChatId))
        XCTAssertFalse(includePeers.peers.contains(pinnedSecretChatId))

        let result = count(folder(includePeers), [
            userId: unread(.contact),
            carriedSecretChatId: unread(.contact),
            pinnedSecretChatId: unread(.contact)
        ], secretChatsByUserId: [
            userId: [carriedSecretChatId]
        ])
        XCTAssertEqual(result.count, 3)
    }
}
