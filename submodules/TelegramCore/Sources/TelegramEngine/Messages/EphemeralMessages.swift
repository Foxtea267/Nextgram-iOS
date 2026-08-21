import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi

private struct PreparedEphemeralMessageSend {
    let peerId: PeerId
    let localId: MessageId
    let botPeerId: PeerId
    let randomId: Int64
    let inputPeer: Api.InputPeer
    let inputUser: Api.InputUser
    let replyTo: Api.InputReplyTo?
    let message: Message
}

func generateEphemeralLocalMessageId(peerId: PeerId, transaction: Transaction) -> MessageId {
    while true {
        var value: Int32 = 0
        arc4random_buf(&value, 4)
        if value == 0 {
            continue
        }
        let id: Int32
        if value == Int32.min {
            id = Int32.min
        } else {
            id = -abs(value)
        }
        let messageId = MessageId(peerId: peerId, namespace: Namespaces.Message.EphemeralLocal, id: id)
        if transaction.getMessage(messageId) == nil {
            return messageId
        }
    }
}

private func generateEphemeralOutgoingRandomId(_ current: Int64? = nil) -> Int64 {
    if let current, current != 0 {
        return current
    }
    while true {
        let value = Int64.random(in: Int64.min ... Int64.max)
        if value != 0 {
            return value
        }
    }
}

private func makeEphemeralStoreMessage(id: MessageId, accountPeerId: PeerId, botPeerId: PeerId, randomId: Int64, timestamp: Int32, text: String, entities: [MessageTextEntity], threadId: Int64?, replyAttribute: ReplyMessageAttribute?, state: EphemeralOutgoingMessageAttribute.State) -> StoreMessage {
    var flags = StoreMessageFlags()
    if state == .sending {
        flags.insert(.Sending)
    }

    var attributes: [MessageAttribute] = [
        TextEntitiesMessageAttribute(entities: entities),
        OutgoingMessageInfoAttribute(uniqueId: randomId, flags: [], acknowledged: false, correlationId: nil, bubbleUpEmojiOrStickersets: [], partialReference: nil),
        EphemeralOutgoingMessageAttribute(botPeerId: botPeerId, randomId: randomId, state: state)
    ]
    if let replyAttribute {
        attributes.append(replyAttribute)
    }

    return StoreMessage(
        id: id,
        customStableId: nil,
        globallyUniqueId: randomId,
        groupingKey: nil,
        threadId: threadId,
        timestamp: timestamp,
        flags: flags,
        tags: [],
        globalTags: [],
        localTags: [],
        forwardInfo: nil,
        authorId: accountPeerId,
        text: text,
        attributes: attributes,
        media: []
    )
}

private func preparedEphemeralReply(replyTo replySubject: EngineMessageReplySubject?, peerId: PeerId, threadId: Int64?, transaction: Transaction) -> (apiReplyTo: Api.InputReplyTo, attribute: ReplyMessageAttribute)? {
    guard let replySubject else {
        return nil
    }

    if replySubject.messageId.namespace == Namespaces.Message.EphemeralLocal {
        guard replySubject.messageId.id > 0 else {
            return nil
        }
        return (
            .inputReplyToEphemeralMessage(.init(id: replySubject.messageId.id)),
            ReplyMessageAttribute(messageId: replySubject.messageId, threadMessageId: nil, quote: nil, isQuote: false, innerSubject: nil)
        )
    }

    guard replySubject.messageId.namespace == Namespaces.Message.Cloud else {
        return nil
    }

    var topMsgId: Int32?
    if let threadId {
        topMsgId = Int32(clamping: threadId)
    }

    var replyFlags: Int32 = 0
    if topMsgId != nil {
        replyFlags |= 1 << 0
    }

    var replyToPeerId: Api.InputPeer?
    if replySubject.messageId.peerId != peerId {
        guard let replyPeer = transaction.getPeer(replySubject.messageId.peerId), let inputReplyPeer = apiInputPeer(replyPeer) else {
            return nil
        }
        replyToPeerId = inputReplyPeer
        replyFlags |= 1 << 1
    }

    var quoteText: String?
    var quoteEntities: [Api.MessageEntity]?
    var quoteOffset: Int32?
    if let replyQuote = replySubject.quote {
        quoteText = replyQuote.text
        replyFlags |= 1 << 2

        if !replyQuote.entities.isEmpty {
            var associatedPeers = SimpleDictionary<PeerId, Peer>()
            for entity in replyQuote.entities {
                for associatedPeerId in entity.associatedPeerIds {
                    if associatedPeers[associatedPeerId] == nil, let associatedPeer = transaction.getPeer(associatedPeerId) {
                        associatedPeers[associatedPeerId] = associatedPeer
                    }
                }
            }
            quoteEntities = apiEntitiesFromMessageTextEntities(replyQuote.entities, associatedPeers: associatedPeers)
            replyFlags |= 1 << 3
        }

        quoteOffset = replyQuote.offset.flatMap { Int32(clamping: $0) }
        if quoteOffset != nil {
            replyFlags |= 1 << 4
        }
    }

    var replyTodoItemId: Int32?
    var replyPollOption: Buffer?
    switch replySubject.innerSubject {
    case let .todoItem(todoItemId):
        replyTodoItemId = todoItemId
        replyFlags |= 1 << 6
    case let .pollOption(pollOption):
        replyPollOption = Buffer(data: pollOption)
        replyFlags |= 1 << 7
    default:
        break
    }

    let threadMessageId = topMsgId.flatMap { MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: $0) }
    return (
        .inputReplyToMessage(.init(flags: replyFlags, replyToMsgId: replySubject.messageId.id, topMsgId: topMsgId, replyToPeerId: replyToPeerId, quoteText: quoteText, quoteEntities: quoteEntities, quoteOffset: quoteOffset, monoforumPeerId: nil, todoItemId: replyTodoItemId, pollOption: replyPollOption)),
        ReplyMessageAttribute(messageId: replySubject.messageId, threadMessageId: threadMessageId, quote: replySubject.quote, isQuote: replySubject.quote != nil, innerSubject: replySubject.innerSubject)
    )
}

private func ephemeralOutgoingStoreMessageWithUpdatedState(_ message: Message, state: EphemeralOutgoingMessageAttribute.State) -> StoreMessage {
    var flags = StoreMessageFlags(message.flags)
    flags.remove(.Unsent)
    flags.remove(.Failed)
    if state == .sending {
        flags.insert(.Sending)
    } else {
        flags.remove(.Sending)
    }

    let attributes = message.attributes.map { attribute -> MessageAttribute in
        if let attribute = attribute as? EphemeralOutgoingMessageAttribute {
            return attribute.withUpdatedState(state)
        } else {
            return attribute
        }
    }

    return StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: flags, tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: message.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: message.author?.id, text: message.text, attributes: attributes, media: message.media)
}

private func enqueueEphemeralTextMessage(account: Account, peerId: PeerId, botPeerId: PeerId, threadId: Int64?, replyTo replySubject: EngineMessageReplySubject?, text: String, entities: [MessageTextEntity], randomId: Int64? = nil) -> Signal<MessageId?, NoError> {
    return account.postbox.transaction { transaction -> MessageId? in
        guard let peer = transaction.getPeer(peerId), let botPeer = transaction.getPeer(botPeerId), apiInputPeer(peer) != nil, apiInputUser(botPeer) != nil else {
            return nil
        }

        let reply = preparedEphemeralReply(replyTo: replySubject, peerId: peerId, threadId: threadId, transaction: transaction)
        let randomId = generateEphemeralOutgoingRandomId(randomId)
        let localId = generateEphemeralLocalMessageId(peerId: peerId, transaction: transaction)
        let timestamp = Int32(account.network.context.globalTime())
        let message = makeEphemeralStoreMessage(id: localId, accountPeerId: account.peerId, botPeerId: botPeerId, randomId: randomId, timestamp: timestamp, text: text, entities: entities, threadId: threadId, replyAttribute: reply?.attribute, state: .sending)
        let _ = transaction.addMessages([message], location: .Random)

        return localId
    }
}

private func preparedEphemeralMessageSend(account: Account, messageId: MessageId, setSending: Bool) -> Signal<PreparedEphemeralMessageSend?, NoError> {
    return account.postbox.transaction { transaction -> PreparedEphemeralMessageSend? in
        guard messageId.namespace == Namespaces.Message.EphemeralLocal, let currentMessage = transaction.getMessage(messageId), let outgoingAttribute = currentMessage.attributes.first(where: { $0 is EphemeralOutgoingMessageAttribute }) as? EphemeralOutgoingMessageAttribute, outgoingAttribute.randomId != 0, let peer = transaction.getPeer(messageId.peerId), let botPeer = transaction.getPeer(outgoingAttribute.botPeerId), let inputPeer = apiInputPeer(peer), let inputUser = apiInputUser(botPeer) else {
            return nil
        }

        let replySubject: EngineMessageReplySubject?
        if let replyAttribute = currentMessage.attributes.first(where: { $0 is ReplyMessageAttribute }) as? ReplyMessageAttribute {
            replySubject = EngineMessageReplySubject(messageId: replyAttribute.messageId, quote: replyAttribute.quote, innerSubject: replyAttribute.innerSubject)
        } else {
            replySubject = nil
        }
        let reply = preparedEphemeralReply(replyTo: replySubject, peerId: messageId.peerId, threadId: currentMessage.threadId, transaction: transaction)

        if setSending {
            transaction.updateMessage(messageId, update: { currentMessage in
                return .update(ephemeralOutgoingStoreMessageWithUpdatedState(currentMessage, state: .sending))
            })
        }

        return PreparedEphemeralMessageSend(peerId: messageId.peerId, localId: messageId, botPeerId: outgoingAttribute.botPeerId, randomId: outgoingAttribute.randomId, inputPeer: inputPeer, inputUser: inputUser, replyTo: reply?.apiReplyTo, message: currentMessage)
    }
}

private func failPendingEphemeralMessage(account: Account, peerId: PeerId, localId: MessageId, randomId: Int64) -> Signal<MessageId?, NoError> {
    return account.postbox.transaction { transaction -> MessageId? in
        let pendingId = transaction.messageIdForGloballyUniqueMessageId(peerId: peerId, id: randomId) ?? localId
        transaction.updateMessage(pendingId, update: { currentMessage in
            return .update(ephemeralOutgoingStoreMessageWithUpdatedState(currentMessage, state: .failed))
        })
        return pendingId
    }
}

private func outgoingEphemeralMessage(from updates: Api.Updates, prepared: PreparedEphemeralMessageSend, accountPeerId: PeerId) -> Api.EphemeralMessage? {
    for update in updates.allUpdates {
        switch update {
        case let .updateNewEphemeralMessage(updateNewEphemeralMessageData):
            let message = updateNewEphemeralMessageData.message
            if case let .ephemeralMessage(messageData) = message {
                if (messageData.flags & (1 << 0)) != 0 && messageData.peerId.peerId == prepared.peerId && messageData.fromId.peerId == accountPeerId && PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(messageData.receiverId)) == prepared.botPeerId {
                    return message
                }
            }
        default:
            break
        }
    }
    return nil
}

func _internal_failStaleEphemeralOutgoingMessages(postbox: Postbox) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        var messageIds: [MessageId] = []
        for peerId in Set(transaction.chatListGetAllPeerIds()) {
            transaction.scanMessageAttributes(peerId: peerId, namespace: Namespaces.Message.EphemeralLocal, limit: Int.max, { id, attributes in
                if attributes.contains(where: { attribute in
                    if let attribute = attribute as? EphemeralOutgoingMessageAttribute {
                        return attribute.state == .sending
                    } else {
                        return false
                    }
                }) {
                    messageIds.append(id)
                }
                return true
            })
        }

        for messageId in messageIds {
            transaction.updateMessage(messageId, update: { currentMessage in
                return .update(ephemeralOutgoingStoreMessageWithUpdatedState(currentMessage, state: .failed))
            })
        }
    }
}

private func completePendingEphemeralMessage(account: Account, prepared: PreparedEphemeralMessageSend, apiMessage: Api.EphemeralMessage) -> Signal<MessageId?, NoError> {
    return account.postbox.transaction { transaction -> MessageId? in
        let message = StoreMessage(apiEphemeralMessage: apiMessage)
        guard case let .Id(serverId) = message.id else {
            return nil
        }

        let pendingId = transaction.messageIdForGloballyUniqueMessageId(peerId: prepared.peerId, id: prepared.randomId) ?? prepared.localId
        let serverAlreadyExists = transaction.getMessage(serverId) != nil

        if serverAlreadyExists {
            if pendingId != serverId {
                transaction.deleteMessages([pendingId], forEachMedia: nil)
            }
            transaction.updateMessage(serverId, update: { _ in
                return .update(message)
            })
        } else if transaction.getMessage(pendingId) != nil {
            transaction.updateMessage(pendingId, update: { _ in
                return .update(message)
            })
        } else {
            let _ = transaction.addMessages([message], location: .Random)
        }

        return serverId
    }
}

private func uploadedContentForPreparedEphemeralMessage(account: Account, prepared: PreparedEphemeralMessageSend) -> Signal<PendingMessageUploadedContentAndReuploadInfo?, NoError> {
    let contentToUpload = messageContentToUpload(accountPeerId: account.peerId, network: account.network, postbox: account.postbox, auxiliaryMethods: account.auxiliaryMethods, transformOutgoingMessageMedia: account.transformOutgoingMessageMedia, messageMediaPreuploadManager: account.messageMediaPreuploadManager, revalidationContext: account.mediaReferenceRevalidationContext, forceReupload: false, isGrouped: false, passFetchProgress: false, message: prepared.message)
    switch contentToUpload {
    case let .immediate(result, _):
        switch result {
        case let .content(content):
            return .single(content)
        case .progress:
            return .single(nil)
        }
    case let .signal(signal, _):
        return signal
        |> filter { result -> Bool in
            if case .content = result {
                return true
            } else {
                return false
            }
        }
        |> take(1)
        |> map { result -> PendingMessageUploadedContentAndReuploadInfo? in
            if case let .content(content) = result {
                return content
            } else {
                return nil
            }
        }
        |> `catch` { _ -> Signal<PendingMessageUploadedContentAndReuploadInfo?, NoError> in
            return .single(nil)
        }
    }
}

private func performPreparedEphemeralMessageSend(account: Account, prepared: PreparedEphemeralMessageSend) -> Signal<MessageId?, NoError> {
    let entitiesAttribute = prepared.message.attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute
    let apiEntities = entitiesAttribute.map { apiTextAttributeEntities($0, associatedPeers: prepared.message.peers) } ?? []
    var flags: Int32 = 0
    if !apiEntities.isEmpty {
        flags |= (1 << 1)
    }
    if prepared.replyTo != nil {
        flags |= (1 << 5)
    }

    return uploadedContentForPreparedEphemeralMessage(account: account, prepared: prepared)
    |> mapToSignal { content -> Signal<MessageId?, NoError> in
        guard let content else {
            return failPendingEphemeralMessage(account: account, peerId: prepared.peerId, localId: prepared.localId, randomId: prepared.randomId)
        }

        let media: Api.InputMedia?
        let messageText: String
        switch content.content {
        case let .text(text):
            media = nil
            messageText = text
        case let .media(inputMedia, text):
            media = inputMedia
            messageText = text
            flags |= (1 << 2)
        default:
            return failPendingEphemeralMessage(account: account, peerId: prepared.peerId, localId: prepared.localId, randomId: prepared.randomId)
        }

        return account.network.request(Api.functions.ephemeral.sendMessage(flags: flags, peer: prepared.inputPeer, receiverId: prepared.inputUser, queryId: nil, message: messageText, entities: apiEntities.isEmpty ? nil : apiEntities, media: media, replyMarkup: nil, richMessage: nil, randomId: prepared.randomId, replyTo: prepared.replyTo))
        |> map { result -> Api.Updates? in
            return result
        }
        |> `catch` { _ -> Signal<Api.Updates?, NoError> in
            return .single(nil)
        }
        |> mapToSignal { result -> Signal<MessageId?, NoError> in
            if let result {
                account.stateManager.addUpdates(result)
                if let message = outgoingEphemeralMessage(from: result, prepared: prepared, accountPeerId: account.peerId) {
                    return completePendingEphemeralMessage(account: account, prepared: prepared, apiMessage: message)
                } else {
                    return failPendingEphemeralMessage(account: account, peerId: prepared.peerId, localId: prepared.localId, randomId: prepared.randomId)
                }
            } else {
                return failPendingEphemeralMessage(account: account, peerId: prepared.peerId, localId: prepared.localId, randomId: prepared.randomId)
            }
        }
    }
}

func _internal_sendEphemeralOutgoingMessage(account: Account, messageId: MessageId) -> Signal<MessageId?, NoError> {
    return preparedEphemeralMessageSend(account: account, messageId: messageId, setSending: false)
    |> mapToSignal { prepared -> Signal<MessageId?, NoError> in
        guard let prepared else {
            return .single(nil)
        }
        return performPreparedEphemeralMessageSend(account: account, prepared: prepared)
    }
}

func _internal_retryEphemeralOutgoingMessage(account: Account, messageId: MessageId) -> Signal<MessageId?, NoError> {
    return preparedEphemeralMessageSend(account: account, messageId: messageId, setSending: true)
    |> mapToSignal { prepared -> Signal<MessageId?, NoError> in
        guard let prepared else {
            return .single(nil)
        }
        return performPreparedEphemeralMessageSend(account: account, prepared: prepared)
    }
}
