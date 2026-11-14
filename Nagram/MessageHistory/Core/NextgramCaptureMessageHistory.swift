import Foundation
import NagramMessageHistory
import NagramSettings
import Postbox

// Compiled into TelegramCore to keep the history persistence module below the engine dependency boundary.
func nextgramCarryMessageHistory(previous: Message, updated: StoreMessage, mediaBox: MediaBox) -> [MessageAttribute] {
    var attributes = nagramPreservingMessageHistory(previous: previous.attributes, updated: updated.attributes)
    guard NagramSettings.shared.saveMessageEditHistory else { return attributes }
    let previousAttributes = previous.attributes.filter { $0 is TextEntitiesMessageAttribute || $0 is RichTextMessageAttribute || $0 is MediaSpoilerMessageAttribute }
    let updatedAttributes = updated.attributes.filter { $0 is TextEntitiesMessageAttribute || $0 is RichTextMessageAttribute || $0 is MediaSpoilerMessageAttribute }
    let oldMedia = previous.media.filter { $0 is TelegramMediaImage || $0 is TelegramMediaFile }
    let newMedia = updated.media.filter { $0 is TelegramMediaImage || $0 is TelegramMediaFile }
    let comparison = NagramMessageEditVersion(text: previous.text, timestamp: previous.timestamp, attributes: previousAttributes, media: oldMedia)
    guard !comparison.contentMatches(text: updated.text, attributes: updatedAttributes, media: newMedia) else { return attributes }
    // Hydrating a rich full page is not an authored edit.
    let oldDate = (previous.attributes.first { $0 is EditedMessageAttribute } as? EditedMessageAttribute)?.date ?? 0
    let newDate = (updated.attributes.first { $0 is EditedMessageAttribute } as? EditedMessageAttribute)?.date ?? 0
    let oldRich = previousAttributes.first { $0 is RichTextMessageAttribute } as? RichTextMessageAttribute
    let newRich = updatedAttributes.first { $0 is RichTextMessageAttribute } as? RichTextMessageAttribute
    if previous.text == updated.text, oldMedia.count == newMedia.count,
       zip(oldMedia, newMedia).allSatisfy({ $0.0.isSemanticallyEqual(to: $0.1) }),
       oldRich?.instantPage == newRich?.instantPage, newDate <= oldDate { return attributes }
    let version = NagramMessageEditVersion(text: previous.text, timestamp: oldDate == 0 ? previous.timestamp : oldDate,
        attributes: previousAttributes, media: oldMedia, imageData: nextgramCachedHistoryImage(previous, mediaBox: mediaBox))
    let history = previous.attributes.first { $0 is NagramMessageHistoryAttribute } as? NagramMessageHistoryAttribute
    attributes.removeAll { $0 is NagramMessageHistoryAttribute }
    attributes.append(NagramMessageHistoryAttribute(appending: version, to: history))
    return attributes
}

private func nextgramCachedHistoryImage(_ message: Message, mediaBox: MediaBox) -> Data? {
    guard message.id.peerId.namespace != Namespaces.Peer.SecretChat, !message.containsSecretMedia, !message.isCopyProtected(),
          let image = message.media.compactMap({ $0 as? TelegramMediaImage }).first else { return nil }
    let representations = image.representations.sorted {
        Int64($0.dimensions.width) * Int64($0.dimensions.height) > Int64($1.dimensions.width) * Int64($1.dimensions.height)
    }
    for representation in representations {
        guard let path = mediaBox.completedResourcePath(representation.resource),
              let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber,
              size.intValue > 0, size.intValue <= NagramMessageEditVersion.maximumImageBytes,
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { continue }
        defer { try? handle.close() }
        if let data = try? handle.read(upToCount: NagramMessageEditVersion.maximumImageBytes + 1),
           !data.isEmpty, data.count <= NagramMessageEditVersion.maximumImageBytes { return data }
    }
    return nil
}
