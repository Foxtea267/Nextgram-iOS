import Foundation
import Postbox
import SwiftSignalKit

public struct NagramDeletedMessagesExportResult {
    public let data: Data
    public let messageCount: Int

    public init(data: Data, messageCount: Int) {
        self.data = data
        self.messageCount = messageCount
    }
}

public enum NagramDeletedMessagesImportResult: Equatable {
    case success(importedCount: Int, skippedCount: Int)
    case invalidArchive
    case wrongAccount
}

private struct NagramArchivedMessageId: Codable {
    let peerId: Int64
    let namespace: Int32
    let id: Int32

    init(_ id: MessageId) {
        self.peerId = id.peerId.toInt64()
        self.namespace = id.namespace
        self.id = id.id
    }

    var messageId: MessageId {
        return MessageId(peerId: PeerId(self.peerId), namespace: self.namespace, id: self.id)
    }
}

private struct NagramArchivedForwardInfo: Codable {
    let authorId: Int64?
    let sourceId: Int64?
    let sourceMessageId: NagramArchivedMessageId?
    let date: Int32
    let authorSignature: String?
    let psaType: String?
    let flags: Int32

    init(_ info: MessageForwardInfo) {
        self.authorId = info.author?.id.toInt64()
        self.sourceId = info.source?.id.toInt64()
        self.sourceMessageId = info.sourceMessageId.map(NagramArchivedMessageId.init)
        self.date = info.date
        self.authorSignature = info.authorSignature
        self.psaType = info.psaType
        self.flags = info.flags.rawValue
    }

    var storeValue: StoreMessageForwardInfo {
        return StoreMessageForwardInfo(
            authorId: self.authorId.map(PeerId.init),
            sourceId: self.sourceId.map(PeerId.init),
            sourceMessageId: self.sourceMessageId?.messageId,
            date: self.date,
            authorSignature: self.authorSignature,
            psaType: self.psaType,
            flags: MessageForwardInfo.Flags(rawValue: self.flags)
        )
    }
}

private struct NagramArchivedDeletedMessage: Codable {
    let id: NagramArchivedMessageId
    let globallyUniqueId: Int64?
    let groupingKey: Int64?
    let threadId: Int64?
    let timestamp: Int32
    let flags: UInt32
    let tags: UInt32
    let globalTags: UInt32
    let localTags: UInt32
    let forwardInfo: NagramArchivedForwardInfo?
    let authorId: Int64?
    let text: String
    let attributes: [Data]
    let media: [Data]

    init(_ message: Message) {
        self.id = NagramArchivedMessageId(message.id)
        self.globallyUniqueId = message.globallyUniqueId
        self.groupingKey = message.groupingKey
        self.threadId = message.threadId
        self.timestamp = message.timestamp
        self.flags = message.flags.rawValue
        self.tags = message.tags.rawValue
        self.globalTags = message.globalTags.rawValue
        self.localTags = message.localTags.rawValue
        self.forwardInfo = message.forwardInfo.map(NagramArchivedForwardInfo.init)
        self.authorId = message.author?.id.toInt64()
        self.text = message.text
        self.attributes = message.attributes.map(Self.encodeObject)
        self.media = message.media.map(Self.encodeObject)
    }

    private static func encodeObject(_ object: PostboxCoding) -> Data {
        let encoder = PostboxEncoder()
        encoder.encodeRootObject(object)
        return encoder.makeData()
    }

    func storeMessage() -> StoreMessage? {
        let decodedAttributes = self.attributes.compactMap { data in
            return PostboxDecoder(buffer: MemoryBuffer(data: data)).decodeRootObject() as? MessageAttribute
        }
        guard decodedAttributes.contains(where: { $0 is NagramDeletedMessageAttribute }), decodedAttributes.count == self.attributes.count else {
            return nil
        }
        let decodedMedia = self.media.compactMap { data in
            return PostboxDecoder(buffer: MemoryBuffer(data: data)).decodeRootObject() as? Media
        }
        guard decodedMedia.count == self.media.count else {
            return nil
        }
        return StoreMessage(
            id: self.id.messageId,
            customStableId: nil,
            globallyUniqueId: self.globallyUniqueId,
            groupingKey: self.groupingKey,
            threadId: self.threadId,
            timestamp: self.timestamp,
            flags: StoreMessageFlags(rawValue: self.flags),
            tags: MessageTags(rawValue: self.tags),
            globalTags: GlobalMessageTags(rawValue: self.globalTags),
            localTags: LocalMessageTags(rawValue: self.localTags),
            forwardInfo: self.forwardInfo?.storeValue,
            authorId: self.authorId.map(PeerId.init),
            text: self.text,
            attributes: decodedAttributes,
            media: decodedMedia
        )
    }
}

private struct NagramDeletedMessagesArchive: Codable {
    let format: String
    let version: Int
    let accountPeerId: Int64
    let createdAt: Int64
    let messages: [NagramArchivedDeletedMessage]
}

public func nagramExportDeletedMessages(postbox: Postbox, accountPeerId: PeerId) -> Signal<NagramDeletedMessagesExportResult?, NoError> {
    return postbox.transaction { transaction -> NagramDeletedMessagesExportResult? in
        var peerIds = Set(transaction.chatListGetAllPeerIds())
        peerIds.insert(accountPeerId)
        var messages: [NagramArchivedDeletedMessage] = []
        for peerId in peerIds {
            transaction.withAllMessages(peerId: peerId, { message in
                if message.attributes.contains(where: { $0 is NagramDeletedMessageAttribute }) {
                    messages.append(NagramArchivedDeletedMessage(message))
                }
                return true
            })
        }
        messages.sort { lhs, rhs in
            if lhs.id.peerId != rhs.id.peerId {
                return lhs.id.peerId < rhs.id.peerId
            }
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.id < rhs.id.id
        }
        let archive = NagramDeletedMessagesArchive(
            format: "nextgram.deleted-messages",
            version: 1,
            accountPeerId: accountPeerId.toInt64(),
            createdAt: Int64(Date().timeIntervalSince1970),
            messages: messages
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(archive) else {
            return nil
        }
        return NagramDeletedMessagesExportResult(data: data, messageCount: messages.count)
    }
}

public func nagramImportDeletedMessages(postbox: Postbox, accountPeerId: PeerId, data: Data) -> Signal<NagramDeletedMessagesImportResult, NoError> {
    guard let archive = try? JSONDecoder().decode(NagramDeletedMessagesArchive.self, from: data), archive.format == "nextgram.deleted-messages", archive.version == 1 else {
        return .single(.invalidArchive)
    }
    guard archive.accountPeerId == accountPeerId.toInt64() else {
        return .single(.wrongAccount)
    }
    return postbox.transaction { transaction -> NagramDeletedMessagesImportResult in
        var importedCount = 0
        var skippedCount = 0
        for record in archive.messages {
            guard let message = record.storeMessage() else {
                skippedCount += 1
                continue
            }
            let id = record.id.messageId
            guard transaction.getMessage(id) == nil else {
                skippedCount += 1
                continue
            }
            let _ = transaction.addMessages([message], location: .Random)
            importedCount += 1
        }
        return .success(importedCount: importedCount, skippedCount: skippedCount)
    }
}
