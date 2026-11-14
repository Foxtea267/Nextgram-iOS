import AccountContext
import Display
import ItemListUI
import NagramSettings
import NagramSettingsSignal
import NagramStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

private struct NextgramHiddenMemberEntry: ItemListNodeEntry {
    let stableId: Int64
    let name: String
    let restore: String

    var section: ItemListSectionId { 0 }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let openRestore = arguments as! (Int64) -> Void
        return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass,
            title: self.name, label: self.restore, sectionId: self.section, style: .blocks, action: { openRestore(self.stableId) })
    }
}

public func nextgramHiddenGroupMembersController(context: AccountContext, chatId: Int64) -> ViewController {
    let accountId = context.account.peerId.toInt64()
    let key = NextgramGroupMemberFilter.key(accountId: accountId, chatId: chatId)
    let peers = nagramStringSignal(key, defaultValue: "")
    |> mapToSignal { _ -> Signal<([Int64], [EnginePeer.Id: EnginePeer]), NoError> in
        let ids = NextgramGroupMemberFilter.hiddenMembers(accountId: accountId, chatId: chatId).sorted()
        guard !ids.isEmpty else { return .single(([], [:])) }
        let items = ids.map { TelegramEngine.EngineData.Item.Peer.Peer(id: EnginePeer.Id($0)) }
        return context.engine.data.get(EngineDataList(items))
        |> map { peers in
            return (ids, Dictionary(uniqueKeysWithValues: peers.compactMap { $0.map { ($0.id, $0) } }))
        }
    }
    var closeWhenEmpty: (() -> Void)?
    let restore: (Int64) -> Void = { id in
        NextgramGroupMemberFilter.setHidden(false, memberId: id, accountId: accountId, chatId: chatId)
        if NextgramGroupMemberFilter.hiddenMembers(accountId: accountId, chatId: chatId).isEmpty {
            closeWhenEmpty?()
        }
    }
    let state = combineLatest(context.sharedContext.presentationData, peers)
    |> deliverOnMainQueue
    |> map { data, result -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = data.strings.baseLanguageCode
        let presentation = ItemListPresentationData(data)
        let entries = result.0.map { id in
            NextgramHiddenMemberEntry(stableId: id, name: result.1[EnginePeer.Id(id)]?.compactDisplayTitle ?? "\(id)",
                restore: ngI18n("Nagram.GroupMemberFilter.Restore", lang))
        }
        return (
            ItemListControllerState(presentationData: presentation, title: .text(ngI18n("Nagram.GroupMemberFilter.Manage", lang)),
                leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)),
            (ItemListNodeState(presentationData: presentation, entries: entries, style: .blocks, animateChanges: false), restore)
        )
    }
    let controller = ItemListController(context: context, state: state)
    controller.navigationPresentation = .default
    closeWhenEmpty = { [weak controller] in controller?.dismiss() }
    return controller
}
