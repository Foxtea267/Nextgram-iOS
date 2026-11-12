import AccountContext
import Foundation
import NagramSettings
import NagramSettingsSignal
import NagramStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit

public func nextgramChatAliasEditorTitle(language: String) -> String {
    return ngI18n("Nagram.ChatAlias.Edit", language)
}

public func nextgramPresentChatAliasEditor(context: AccountContext, peer: EnginePeer) {
    let accountPeerId = context.account.peerId.toInt64()
    let peerId = peer.id.toInt64()
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let strings = presentationData.strings
    let language = strings.baseLanguageCode
    let alert = UIAlertController(title: nextgramChatAliasEditorTitle(language: language),
                                  message: ngI18n("Nagram.ChatAlias.Hint", language), preferredStyle: .alert)
    alert.addTextField { field in
        field.placeholder = peer.compactDisplayTitle
        field.text = NextgramChatAliases.name(accountPeerId: accountPeerId, peerId: peerId)
    }
    alert.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel))
    alert.addAction(UIAlertAction(title: strings.Common_Done, style: .default) { [weak alert] _ in
        guard let field = alert?.textFields?.first else { return }
        NextgramChatAliases.set(field.text ?? "", accountPeerId: accountPeerId, peerId: peerId)
    })
    context.sharedContext.applicationBindings.presentNativeController(alert)
}

public func nextgramSearchLocalPeers(context: AccountContext, query: String, scope: TelegramSearchPeersScope = .everywhere) -> Signal<[EngineRenderedPeer], NoError> {
    let original = context.engine.contacts.searchLocalPeers(query: query, scope: scope)
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty, scope == .everywhere || scope == .channels else { return original }

    let matches = nextgramChatAliasesSignal(accountPeerId: context.account.peerId.toInt64())
    |> mapToSignal { names -> Signal<[EngineRenderedPeer], NoError> in
        let ids = names.compactMap { id, name -> EnginePeer.Id? in
            guard name.localizedStandardContains(term), let value = Int64(id) else { return nil }
            return EnginePeer.Id(value)
        }
        guard !ids.isEmpty else { return .single([]) }
        return context.engine.data.subscribe(EngineDataList(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
        |> map { peers in
            return peers.compactMap { peer -> EngineRenderedPeer? in
                guard let peer else { return nil }
                switch peer {
                case let .channel(channel) where channel.participationStatus == .member:
                    if scope == .channels {
                        guard case .broadcast = channel.info else { return nil }
                    }
                    return EngineRenderedPeer(peer: peer)
                case let .legacyGroup(group) where scope == .everywhere && group.membership == .Member:
                    return EngineRenderedPeer(peer: peer)
                default:
                    return nil
                }
            }
        }
    }
    return combineLatest(original, matches)
    |> map { peers, matches in
        let peerIds = Set(peers.map(\.peerId))
        return peers + matches.filter { !peerIds.contains($0.peerId) }
    }
}
