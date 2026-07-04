import AccountContext
import Foundation
import NagramSettings
import Postbox
import SwiftSignalKit
import TelegramCore

// MARK: NAGRAM — Unified Nagram translation facade. Telegram provider reuses TelegramEngine MTProto translateText wrappers.
public final class NagramTranslateService {
    private let context: AccountContext

    public init(context: AccountContext) {
        self.context = context
    }

    public var provider: NagramTranslationProvider {
        return NagramSettings.shared.translationProviderValue
    }

    public func translate(text: String, toLang: String, entities: [MessageTextEntity] = [], tone: TranslationTone = .neutral, messageId: EngineMessage.Id? = nil, fromLang: String? = nil) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
        let provider = self.provider
        switch provider {
        case .telegram:
            return self.context.engine.messages.translate(text: text, toLang: toLang, entities: entities, tone: tone, messageId: messageId)
        case .google, .googleCN, .microsoft, .yandex, .transmart, .llm:
            return nagramExternalTranslate(provider: provider, text: text, fromLang: fromLang, toLang: toLang)
        }
    }

    public func translateMessages(messageIds: [EngineMessage.Id], fromLang: String?, toLang: String, enableLocalIfPossible: Bool, tone: TranslationTone = .neutral) -> Signal<Never, TranslationError> {
        let provider = self.provider
        switch provider {
        case .telegram:
            return self.context.engine.messages.translateMessages(messageIds: messageIds, fromLang: fromLang, toLang: toLang, enableLocalIfPossible: enableLocalIfPossible, tone: tone)
        case .google, .googleCN, .microsoft, .yandex, .transmart, .llm:
            return self.translateMessagesExternally(provider: provider, messageIds: messageIds, fromLang: fromLang, toLang: toLang)
        }
    }

    private func translateMessagesExternally(provider: NagramTranslationProvider, messageIds: [EngineMessage.Id], fromLang: String?, toLang: String) -> Signal<Never, TranslationError> {
        return self.context.account.postbox.transaction { transaction -> [(EngineMessage.Id, String)] in
            var items: [(EngineMessage.Id, String)] = []
            for messageId in messageIds {
                guard let message = transaction.getMessage(messageId) else {
                    continue
                }
                if !message.text.isEmpty {
                    items.append((messageId, message.text))
                } else if let audioTranscription = message.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute, !audioTranscription.text.isEmpty && !audioTranscription.isPending {
                    items.append((messageId, audioTranscription.text))
                }
            }
            return items
        }
        |> castError(TranslationError.self)
        |> mapToSignal { items -> Signal<Never, TranslationError> in
            guard !items.isEmpty else {
                return .complete()
            }
            let timeoutSeconds: Double = provider == .llm ? 45.0 : 15.0
            let signals: [Signal<(EngineMessage.Id, String)?, NoError>] = items.map { messageId, text in
                return nagramExternalTranslate(provider: provider, text: text, fromLang: fromLang, toLang: toLang)
                |> timeout(timeoutSeconds, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.generic))
                |> map { result -> (EngineMessage.Id, String)? in
                    guard let translatedText = result?.0, !translatedText.isEmpty else {
                        return nil
                    }
                    return (messageId, translatedText)
                }
                |> `catch` { _ -> Signal<(EngineMessage.Id, String)?, NoError> in
                    return .single(nil)
                }
            }
            return combineLatest(signals)
            |> mapToSignal { translations -> Signal<Never, NoError> in
                let translations = translations.compactMap { $0 }
                guard !translations.isEmpty else {
                    return .complete()
                }
                return self.context.account.postbox.transaction { transaction in
                    for (messageId, text) in translations {
                        transaction.updateMessage(messageId, update: { currentMessage in
                            let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                            var attributes = currentMessage.attributes.filter { !($0 is TranslationMessageAttribute) }
                            attributes.append(TranslationMessageAttribute(text: text, entities: [], toLang: toLang))
                            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                        })
                    }
                }
                |> ignoreValues
            }
            |> castError(TranslationError.self)
        }
    }
}
