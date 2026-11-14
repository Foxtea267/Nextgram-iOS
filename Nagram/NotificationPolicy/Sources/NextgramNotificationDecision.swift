import NagramSettings
import TelegramCore

/// Classification only. Never revives muted, read, imported or otherwise ineligible messages.
public func nextgramNotificationMode(message: EngineMessage, accountPeerId: EnginePeer.Id) -> NextgramNotificationMode {
    var categories: [String] = []
    if message.media.contains(where: { media in
        guard let action = media as? TelegramMediaAction else { return false }
        if case .pinnedMessageUpdated = action.action { return true }
        return false
    }) { categories.append("pin") }
    if message.attributes.contains(where: { attribute in
        guard let info = attribute as? NotificationInfoMessageAttribute else { return false }
        return info.flags.contains(.personal)
    }) { categories.append("mention") }
    if message.attributes.contains(where: { attribute in
        guard let reply = attribute as? ReplyMessageAttribute, let original = message.associatedMessages[reply.messageId] else { return false }
        return original.author?.id == accountPeerId
    }) { categories.append("reply") }
    let modes = categories.map { NextgramNotificationPolicy.mode(for: $0) }
    if modes.contains(.off) { return .off }
    return modes.contains(.silent) ? .silent : .default
}
