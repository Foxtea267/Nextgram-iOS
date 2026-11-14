import AccountContext
import Display
import ItemListUI
import NagramSettings
import NagramSettingsSignal
import NagramStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

private struct MemberNotificationEntry: ItemListNodeEntry {
    let stableId: Int64
    let name: String
    let label: String
    var section: ItemListSectionId { 0 }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let remove = arguments as! (Int64) -> Void
        if self.stableId == 0 {
            return ItemListTextItem(presentationData: presentationData, text: .plain(self.name), sectionId: self.section)
        }
        return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: self.name,
            label: self.label, sectionId: self.section, style: .blocks, action: { remove(self.stableId) })
    }
}

public func nextgramMemberNotificationsController(context: AccountContext, chatId: Int64? = nil) -> ViewController {
    let accountId = context.account.peerId.toInt64()
    let key = chatId.map { NextgramMemberNotifications.key(accountId: accountId, chatId: $0) }
        ?? "nextgram.memberNotificationsRevision.\(accountId)"
    let members = (nagramStringSignal(key, defaultValue: "") |> deliverOnMainQueue)
    |> mapToSignal { _ -> Signal<([Int64], [EnginePeer.Id: EnginePeer]), NoError> in
        let ids = chatId.map { NextgramMemberNotifications.members(accountId: accountId, chatId: $0).sorted() }
            ?? NextgramMemberNotifications.chats(accountId: accountId)
        guard !ids.isEmpty else { return .single(([], [:])) }
        return context.engine.data.get(EngineDataList(ids.map { TelegramEngine.EngineData.Item.Peer.Peer(id: EnginePeer.Id($0)) }))
        |> map { peers in (ids, Dictionary(uniqueKeysWithValues: peers.compactMap { $0.map { ($0.id, $0) } })) }
    }
    var openGroup: ((Int64) -> Void)?
    let remove: (Int64) -> Void = { id in
        if let chatId { NextgramMemberNotifications.setEnabled(false, memberId: id, accountId: accountId, chatId: chatId) }
        else { openGroup?(id) }
    }
    let state = combineLatest(context.sharedContext.presentationData, members)
    |> deliverOnMainQueue
    |> map { data, members -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let language = data.strings.baseLanguageCode
        let presentation = ItemListPresentationData(data)
        var entries = [MemberNotificationEntry(stableId: 0, name: ngI18n("Nagram.MemberNotifications.Hint", language), label: "")]
        entries += members.0.map { id in
            MemberNotificationEntry(stableId: id, name: members.1[EnginePeer.Id(id)]?.compactDisplayTitle ?? "\(id)",
                label: chatId == nil ? "" : ngI18n("Nagram.MemberNotifications.Disable", language))
        }
        return (ItemListControllerState(presentationData: presentation, title: .text(ngI18n("Nagram.MemberNotifications.Manage", language)),
            leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)),
            (ItemListNodeState(presentationData: presentation, entries: entries, style: .blocks, animateChanges: false), remove))
    }
    let controller = ItemListController(context: context, state: state)
    controller.navigationPresentation = .default
    openGroup = { [weak controller] id in controller?.push(nextgramMemberNotificationsController(context: context, chatId: id)) }
    return controller
}
