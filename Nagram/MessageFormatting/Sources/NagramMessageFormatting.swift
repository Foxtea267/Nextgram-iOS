import Foundation
import NagramSettings
import TelegramCore

public func nagramApplyDefaultMessageFormat(_ message: EnqueueMessage) -> EnqueueMessage {
    let format = NagramSettings.shared.defaultMessageFormatValue
    guard format != .plain, case let .message(text, attributes, _, _, _, _, _, _, _, _) = message, !text.isEmpty else {
        return message
    }

    let entities = attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.flatMap { $0.entities }
    // Manual formatting (including Markdown) always takes priority over the default.
    for entity in entities {
        switch entity.type {
        case .Bold, .Italic, .Code, .Pre, .Underline, .Strikethrough, .Spoiler, .BlockQuote:
            return message
        default:
            break
        }
    }

    let type: MessageTextEntityType
    switch format {
    case .plain:
        return message
    case .bold:
        type = .Bold
    case .italic:
        type = .Italic
    case .monospace:
        // Code entities cannot overlap links, mentions, or custom emoji.
        guard entities.isEmpty else {
            return message
        }
        type = .Code
    case .underline:
        type = .Underline
    case .strikethrough:
        type = .Strikethrough
    case .spoiler:
        type = .Spoiler
    }

    let styledEntities = [MessageTextEntity(range: 0 ..< text.utf16.count, type: type)] + entities
    return message.withUpdatedAttributes { attributes in
        var attributes = attributes.filter { !($0 is TextEntitiesMessageAttribute) }
        attributes.append(TextEntitiesMessageAttribute(entities: styledEntities))
        return attributes
    }
}
