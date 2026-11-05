import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import AdminUserActionsSheet

// MARK: NAGRAM — 成员列表的「移除」打开 AdminUserActionsSheet，可同时删除其全部消息、举报，或改为限制。
extension PeerInfoScreenNode {
    func nagramPresentRemoveMemberActions(chatPeer: EnginePeer, participant: RenderedChannelParticipant) {
        let chatPeerId = chatPeer.id
        let memberId = participant.peer.id
        let deleteAllMessageCount = self.context.engine.messages.getSearchMessageCount(location: .peer(peerId: chatPeerId, fromId: memberId, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "")
        |> take(1)

        let _ = (deleteAllMessageCount
        |> deliverOnMainQueue).startStandalone(next: { [weak self] count in
            guard let self else {
                return
            }
            let sheet = AdminUserActionsSheet(
                context: self.context,
                chatPeer: chatPeer,
                peers: [participant],
                mode: .chat(messageCount: 0, deleteAllMessageCount: count, completion: { [weak self] result in
                    self?.nagramApplyRemoveMemberActions(chatPeerId: chatPeerId, result: result)
                })
            )
            self.controller?.push(sheet)
        })
    }

    private func nagramApplyRemoveMemberActions(chatPeerId: EnginePeer.Id, result: AdminUserActionsSheet.ChatResult) {
        let engine = self.context.engine
        for authorId in result.deleteAllFromPeers {
            let _ = engine.messages.deleteAllMessagesWithAuthor(peerId: chatPeerId, authorId: authorId, namespace: Namespaces.Message.Cloud).startStandalone()
            let _ = engine.messages.clearAuthorHistory(peerId: chatPeerId, memberId: authorId).startStandalone()
        }
        for authorId in result.deleteAllReactionsFromPeers {
            let _ = engine.messages.deleteAllReactionsWithAuthor(peerId: chatPeerId, authorId: authorId).startStandalone()
        }
        for authorId in result.reportSpamPeers {
            let _ = engine.peers.reportPeer(peerId: authorId, reason: .spam, message: "").startStandalone()
        }
        // 走成员列表自己的移除，列表立即去掉这一行
        for authorId in result.banPeers {
            self.data?.members?.membersContext.removeMember(memberId: authorId)
        }
        for (authorId, rights) in result.updateBannedRights {
            let _ = engine.peers.updateChannelMemberBannedRights(peerId: chatPeerId, memberId: authorId, rights: rights).startStandalone()
        }
        if let banFromCommunity = result.banFromCommunity {
            let _ = engine.peers.toggleCommunityParticipantBanned(communityId: banFromCommunity.communityId, participantId: banFromCommunity.participantId, banned: true).startStandalone()
        }
    }
}
